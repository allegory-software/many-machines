# mm lib: functions reading var/machines and var/deploys on the mm machine.

# mm module ------------------------------------------------------------------

install_mm() {
	checkvars MM_REPO
	package_install autossh sshfs jq sysbench
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

is_running_mon() { service_is_running mm-mon; }
start_mon()      { service_start      mm-mon; }
stop_mon()       { service_stop       mm-mon; }
version_mon()    { version_mm; }

install_mon() {

	package_install sensors nvme-cli

	save "
[Unit]
Description=mm runtime monitor service
After=multi-user.target
After=network-online.target
Requires=network-online.target

# try restarting for 60s
StartLimitIntervalSec=60

# try restarting 1 times
StartLimitBurst=1

[Service]
Type=simple

# skip monitoring the first 10s to give time for other services to start
ExecStartPre=/bin/sh -c '[ \"$SYSTEMD_INVOCATION_ID\" != \"\" ] && sleep 10 || true'
ExecStart=/root/mm/cmd/mon systemd
WorkingDirectory=/root/mm
StandardOutput=null
StandardError=null

# restart only if exit code != 0
Restart=on-failure

# wait 1s before restarting
RestartSec=1

[Install]
WantedBy=multi-user.target

" /etc/systemd/system/mm-mon.service

	systemctl daemon-reload
	service_enable mm-mon.service
}

uninstall_mon() {
	service_disable mm-mon.service
	rm_file /etc/systemd/system/mm-mon.service
}

# var dir ops ----------------------------------------------------------------

var_unlock() { # KEY
	local KEY=$1
	checkvars KEY-
	package_version git-crypt >/dev/null || package_install git-crypt
	(
	must cd /root/mm/var
	on_exit run rm -f ../var_git_crypt_key
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

this_machine() { R1=`basename "$(readlink machine)" 2>/dev/null`; }
this_deploy()  { R1=`basename "$(readlink deploy)" 2>/dev/null`; }

check_deploy() { # DEPLOY
	checknosp "$1" "DEPLOY required"
	[[ -d var/deploys/$1 ]] || die "Deployment unknown: $1"
}
check_machine() { # MACHINE
	checknosp "$1" "MACHINE required"
	[[ -d var/machines/$1 ]] || die "Machine unknown: $1"
}

try_machine_of_deploy() {
	check_deploy "$1"
	R1=$(basename $(readlink var/deploys/$1/machine) 2>/dev/null)
}
machine_of_deploy() { # DEPLOY
	try_machine_of_deploy "$@"
	[[ $R1 ]] || die "No machine set for deploy: $1."
}

# TODO: finish this and use it
md_resolve() { # DEPLOY|MACHINE|@DEPLOY|GROUP|. ...
	local MACHINES= DEPLOYS=
	local -A m # mm[NAME]=1
	local arg
	for arg in "$@"; do
		checknosp "$arg"
		[[ $arg == @* ]] && {
			arg=${arg:1}
			machine_of_deploy $arg; MACHINES+=" $R1"
			continue
		}
		[[ $arg == . ]] && { this_machine; arg=$R1; }
		[[ $m[$arg] ]] && continue
		m[$arg]=1
		[[ -d var/deploys/$arg  ]] && { DEPLOYS+=" $arg"; continue; }
		[[ -d var/machines/$arg ]] && { MACHINES+=" $arg"; continue; }
		[[ -d var/groups/$arg   ]] && {
			local g
			for g in `ls -1 var/groups/$arg`; do
				[[ $m[$arg] ]] && continue
				m[$arg]=1
				[[ -d var/deploys/$arg  ]] && { DEPLOYS+=" $arg"; continue; }
				[[ -d var/machines/$arg ]] && { MACHINES+=" $arg"; continue; }
			done
		}
	done
	R1=$MACHINES R2=$DEPLOYS
}

check_md_new_name() { # MACHINE|DEPLOY
	local NAME=$1
	checkvars NAME
	[[ ! -d var/deploys/$NAME  ]] || die "A deploy with this name already exists: '$NAME'."
	[[ ! -d var/machines/$NAME ]] || die "A machine with this name already exists: '$NAME'."
}

machine_of() { # MACHINE|DEPLOY -> MACHINE, [DEPLOY]
	checknosp "$1" "MACHINE or DEPLOY required"
	if [[ -d var/deploys/$1 ]]; then
		machine_of_deploy $1; R2=$1
	elif [[ -d var/machines/$1 ]]; then
		R1=$1; R2=
	else
		die "No MACHINE or DEPLOY named: '$1'"
	fi
}

ip_of() { # MD -> IP, MACHINE, 'LOCAL|PUBLIC'
	machine_of "$1"; local m1=$R1
	local DEPLOY= # so md_var uses MACHINE not DEPLOY
	this_machine; local m0=$R1
	local kind=public
	if [[ $m1 == $m0 ]]; then
		kind=local
	else
		MACHINE=$m0 md_var local_subnet; local m0_subnet=$R1
		MACHINE=$m1 md_var local_subnet; local m1_subnet=$R1
		if [[ $m0_subnet && $m0_subnet == $m1_subnet ]]; then
			kind=local
		fi
	fi
	MACHINE=$m1 md_var ${kind}_ip || die "Machine $m1 has no ${kind}_ip."
	R2=$m1 R3=$kind
}

ip_port_of() { # MD SERVICE -> IP, PORT, MACHINE
	local md=$1 service=$2
	ip_of "$md"; local ip=$R1 m=$R2 kind=$R3
	MACHINE=$m md_var ${kind}_port_${service}; local port=$R1
	R1=$ip R2=$port R3=$m
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

machine_is_active() { # MACHINE=
	this_machine; [[ $MACHINE == $R1 ]] && return 0
	DEPLOY= md_var ACTIVE 0; [[ $R1 != 0 ]] || return 1
}

deploy_is_active() { # DEPLOY=
	md_var ACTIVE 0; [[ $R1 != 0 ]] || return 1
	try_machine_of_deploy $DEPLOY || return 2
	MACHINE=$R1 machine_is_active || return 2
}

active_machines() { # [NOTHIS=1]
	local S
	local MACHINE
	for MACHINE in `ls -1 machines 2>/dev/null || ls -1 var/machines 2>/dev/null`; do
		if [[ $INACTIVE ]] || machine_is_active; then
			[[ $NOTHIS && $MACHINE == $THIS_MACHINE ]] && continue
			S+=" $MACHINE"
		fi
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
each_machine() { # [NOTHIS=1] [NOALL=1] [ALL=1] [NOSUBPROC=1] MACHINES= DEPLOYS= COMMAND ARGS...
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
		[[ $NOTHIS && $MACHINE == $THIS_MACHINE ]] && {
			say "Excluding this machine."
			continue
		}
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
