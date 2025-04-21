# mm lib: functions reading var/machines and var/deploys on the mm machine.

# mm module ------------------------------------------------------------------

install_mm() {
	checkvars MM_REPO
	apt_get_install autossh sshfs
	git_clone_for root $MM_REPO /root/mm master
	(
	must cd /root/mm
	./install
	)
}

postinstall_mm() {
	mm $MACHINE var-sync
}

uninstall_mm() {
	/root/mm/uninstall
	rm_dir /root/mm
}

install_mm_var() {
	checkvars MM_VAR_REPO
	git_clone_for root $MM_VAR_REPO /root/mm/var master
}

# mm_var package installs the encrypted mm var dir which contains the entire mm database.
# only install this module on trusted machines that you want to use mm on.
postinstall_mm_var() {
	local VAR_LOCK_KEY=`var_lock_key` || die "var_lock_key error: $?"
	ssh_script var_unlock "$VAR_LOCK_KEY"
}

uninstall_mm_var() {
	rm_dir /root/mm/var
}

version_mm() {
	(
	must cd /root/mm
	must git rev-parse --short HEAD
	)
}

# mm monitor service ---------------------------------------------------------

mon_pid() { pgrep -f 'bin/bash cmd/mon daemon'; }

is_running_mon() { mon_pid >/dev/null; }

# var dir ops ----------------------------------------------------------------

var_unlock() { # KEY
	local KEY=$1
	checkvars KEY-
	package_version git-crypt >/dev/null || package_install git-crypt
	(
	must cd /root/mm/var
	#on_exit run rm -f ../var_git_crypt_key
	printf "%s" "$KEY" | must base64 -d - > ../var_git_crypt_key
	must git-crypt unlock ../var_git_crypt_key
	)
}

var_lock_key() {
	(
	must cd /root/mm/var
	git-crypt export-key /proc/self/fd/1 | base64 -
	)
}

# machines and deploys db ----------------------------------------------------

check_machine() { # MACHINE
	checknosp "$1" "MACHINE required"
	[[ -d var/machines/$1 ]] || die "Machine unknown: $1"
}

check_deploy() { # DEPLOY
	checknosp "$1" "DEPLOY required"
	[[ -d var/deploys/$1 ]] || die "Deployment unknown: $1"
}

check_md_new_name() { # MACHINE|DEPLOY
	local NAME=$1
	checkvars NAME
	[[ ! -d var/deploys/$NAME  ]] || die "A deploy with this name already exists: '$NAME'."
	[[ ! -d var/machines/$NAME ]] || die "A machine with this name already exists: '$NAME'."
}

try_machine_of_deploy() {
	check_deploy "$1"
	R1=$(basename $(readlink var/deploys/$1/machine) 2>/dev/null)
}
machine_of_deploy() { # DEPLOY
	try_machine_of_deploy "$@"
	[[ $R1 ]] || die "No machine set for deploy: $1."
}

machine_of() { # MACHINE|DEPLOY -> MACHINE, [DEPLOY]
	checknosp "$1" "MACHINE or DEPLOY required"
	if [[ -d var/deploys/$1 ]]; then
		machine_of_deploy $1; R3=$1
	elif [[ -d var/machines/$1 ]]; then
		R1=$1
	else
		die "No MACHINE or DEPLOY named: '$1'"
	fi
}

ip_of() { # MD -> IP, MACHINE, [DEPLOY]
	machine_of "$1"; R2=$R1
	checkfile var/machines/$R2/public_ip
	R1=$(cat $R1)
}

machine_by_ip() { # IP
	local IP=$1
	checkvars IP
	local m
	for m in `ls -1 var/machines`; do
		ip_of $m; [[ $IP == $R1 ]] && { R1=$m; return 0; }
	done
	R1=$IP
	return 1
}

this_machine() {
	R1=`basename "$(readlink machine)" 2>/dev/null`
}

machine_is_active() { # MACHINE=
	this_machine; [[ $MACHINE == $R1 ]] && return 0
	DEPLOY= md_var ACTIVE 0; [[ $R1 != 0 ]] || return 1
}

deploy_is_active() { # DEPLOY=
	md_var ACTIVE 0; [[ $R1 != 0 ]] || return 1
	try_machine_of_deploy $DEPLOY || return 2
	MACHINE=$R1 machine_is_active || return 2
}

active_machines() {
	local S
	local MACHINE
	for MACHINE in `ls -1 machines 2>/dev/null || ls -1 var/machines 2>/dev/null`; do
		if [[ $INACTIVE ]] || machine_is_active; then  S+=" $MACHINE"; fi
	done
	R1=$S
}

active_deploys() {
	local S
	local DEPLOY
	for DEPLOY in `ls -1 deploys 2>/dev/null || ls -1 var/deploys 2>/dev/null`; do
		if [[ $INACTIVE ]] || deploy_is_active; then S+=" $DEPLOY"; fi
	done
	R1=$S
}

# NOTE: set NOALL=1 for dangerous commands. User will set ALL=1 to override.
# NOTE: set NOSUBPROC=1 to break on first error.
each_machine() { # [NOALL=1] [ALL=1] [NOSUBPROC=1] MACHINES= DEPLOYS= COMMAND ARGS...
	declare -A mm
	local M D
	local MACHINES="$MACHINES"
	for M in $MACHINES; do
		check_machine $M
		mm[$M]=1
	done
	for D in $DEPLOYS; do
		machine_of $D; M=$R1
		[[ ${mm[$M]} ]] && continue
		mm[$M]=1
		MACHINES+=" $M"
	done
	if [[ ${#mm[@]} == 0 ]]; then
		[[ $NOALL && ! $ALL ]] && die "MACHINE(s) required"
		active_machines
		MACHINES="$R1"
	fi
	[[ ! $QUIET && ${#mm[@]} == 1 ]] && QUIET=1
	local CMD="$1"; shift
	local MACHINE
	for MACHINE in $MACHINES; do
		[[ $QUIET ]] || say "On machine $MACHINE:"
		if [[ $NOSUBPROC ]]; then
			"$CMD" "$@"
		else
			("$CMD" "$@")
		fi
	done
}

each_deploy() { # [NOALL=1] [ALL=1] [NOSUBPROC=1] MACHINES="" DEPLOYS= COMMAND ARGS...
	local DEPLOYS="$DEPLOYS"
	if [[ $DEPLOYS ]]; then
		for DEPLOY in $DEPLOYS; do
			check_deploy $DEPLOY
		done
	else
		[[ $NOALL && ! $ALL ]] && die "DEPLOY(s) required"
		active_deploys
		DEPLOYS=$R1
	fi
	local CMD=$1; shift
	for DEPLOY in $DEPLOYS; do
		try_machine_of_deploy $DEPLOY; local MACHINE=$R1
		[[ $QUIET ]] || say "On deploy $DEPLOY:"
		if [[ $NOSUBPROC ]]; then
			"$CMD" "$@"
		else
			("$CMD" "$@")
		fi
	done
}

_each_deploy_with_domain() {
	if md_var DOMAIN; then
		local DOMAIN=$R1
		(DOMAIN=$DOMAIN "$@")
	fi
}
each_deploy_with_domain() {
	each_deploy _each_deploy_with_domain "$@"
}

_each_deploy_with_ssl() {
	if md_var DOMAIN; then
		local DOMAIN=$R1
		md_var NOSSL && return
		(DOMAIN=$DOMAIN "$@")
	fi
}
each_deploy_with_ssl() {
	each_deploy _each_deploy_with_ssl "$@"
}

each_md() {
	if [[ $MM_DEPLOY ]]; then
		each_deploy "$@"
	else
		each_machine "$@"
	fi
}
