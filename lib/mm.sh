# mm lib: functions reading var/machines and var/deploys on the mm machine.

# mm module ------------------------------------------------------------------

preinstall_mm() {
	local VAR_LOCK_KEY=`var_lock_key` || die "var_lock_key error: $?"
	VARS="VAR_LOCK_KEY" ssh_script '
	git_clone_for root git@github.com:allegory-software/many-machines /root/mm master
	(
	must cd /root/mm
	./install
	git_clone_for root git@github.com:allegory-software/mm-var /root/mm/var master
	var_unlock "$VAR_LOCK_KEY"
	)
	'
}

install_mm() {
	true
}

version_mm() {
	(
	must cd /root/mm
	must git rev-parse --short HEAD
	)
}

# var dir ops ----------------------------------------------------------------

var_git_init() { # REPO
	local REPO=$1
	checkvars REPO
	package_version git-crypt >/dev/null || package_install git-crypt
	[[ -d var/.git ]] && die "Remove var/.git first."
	[[ -f var/.gitattributes ]] && die "Remove var/.gitattributes first."
	must mkdir -p var
	(
	must cd var
	must chmod 770 .
	git init
	save "\
* filter=git-crypt diff=git-crypt
.gitattributes !filter !diff
" .gitattributes
	must git-crypt init
	must git add .
	must git commit -m "init"
	must git remote add origin $REPO
	must git push -u origin master
	)
}

var_clone() { # REPO
	local REPO=$1
	checkvars REPO
	on_exit run rm -rf var.new
	git_clone_for root $REPO var.new
	must mv --backup=numbered var.new var
	must chmod 770 var
}

var_pull() {
	(
	must cd var
	must git pull
	)
}

var_push() { # [COMMIT_MSG]
	(
	must cd var
	must git add .
	run git diff --quiet && run git diff --staged --quiet || \
		must git commit -m "${COMMIT_MSG:-unimportant}"
	must git push
	)
}

var_unlock() { # KEY
	local KEY=$1
	checkvars KEY-
	package_version git-crypt >/dev/null || package_install git-crypt
	(
	must cd var
	#on_exit run rm -f ../var_git_crypt_key
	printf "%s" "$KEY" | must base64 -d - > ../var_git_crypt_key
	must git-crypt unlock ../var_git_crypt_key
	)
}

var_lock_key() {
	(
	must cd var
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

machine_is_active() {
	DEPLOY= md_var ACTIVE 0
	[[ $R1 != 0 ]]; return $?
}

deploy_is_active() {
	md_var ACTIVE 0
	[[ $R1 != 0 ]]; return $?
}

active_machines() {
	local S
	local MACHINE
	for MACHINE in `[ -d machines ] && ls -1 machines || ls -1 var/machines`; do
		if [[ $INACTIVE ]] || machine_is_active; then  S+=" $MACHINE"; fi
	done
	R1=$S
}

active_deploys() {
	local S
	local DEPLOY
	for DEPLOY in `[ -d deploys ] && ls -1 deploys || ls -1 var/deploys`; do
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
		[[ $NOALL  && ! $ALL ]] && die "MACHINE(s) required"
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
