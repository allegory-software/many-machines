# mm lib: functions reading var/machines and var/deploys on the mm machine.

# mm module ------------------------------------------------------------------

install_mm() {
	git_clone_for root git@github.com:allegory-software/many-machines2 /opt/mm master mm
	# install globally
	must ln -sf /opt/mm/mm      /usr/bin/mm
	must ln -sf /opt/mm/mmd     /usr/bin/mmd
	must ln -sf /opt/mm/lib/all /usr/bin/mmlib
	remove_line /opt/mm/mm-autocomplete.sh /root/.bashrc
	append ". /opt/mm/mm-autocomplete.sh" /root/.bashrc
}

version_mm() {
	(
	must cd /opt/mm
	must git rev-parse --short HEAD
	)
}

# machines and deploys db ----------------------------------------------------

check_machine() { # MACHINE
	checknosp "$1" "MACHINE required"
	[ -d var/machines/$1 ] || die "Machine unknown: $1"
}

check_deploy() { # DEPLOY
	checknosp "$1" "DEPLOY required"
	[ -d var/deploys/$1 ] || die "Deployment unknown: $1"
}

machine_of_deploy() { # DEPLOY
	check_deploy "$1"
	R1=$(basename $(readlink var/deploys/$1/machine))
	[ "$R1" ] || die "No machine set for deploy: $1."
}

machine_of() { # MACHINE|DEPLOY -> MACHINE, , [DEPLOY]
	checknosp "$1" "MACHINE or DEPLOY required"
	if [ -d var/deploys/$1 ]; then
		machine_of_deploy $1; R3=$1
	elif [ -d var/machines/$1 ]; then
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

machine_is_active() {
	machine_var ACTIVE 0
	[[ $R1 != 0 ]]; return $?
}

deploy_is_active() {
	deploy_var ACTIVE 0
	[[ $R1 != 0 ]]; return $?
}

active_machines() {
	local S
	local MACHINE
	for MACHINE in `ls -1 var/machines`; do
		if [[ $INACTIVE ]] || machine_is_active; then  S+=" $MACHINE"; fi
	done
	R1=$S
}

active_deploys() {
	local S
	local DEPLOY
	for DEPLOY in `ls -1 var/deploys`; do
		if [[ $INACTIVE ]] || deploy_is_active; then S+=" $DEPLOY"; fi
	done
	R1=$S
}

# NOTE: set NOALL=1 for dangerous commands. User will set ALL=1 to override.
# NOTE: set NOSUBPROC=1 to break on first error.
each_machine() { # [NOALL=] [ALL=] [NOSUBPROC=1] MACHINES= DEPLOYS= COMMAND ARGS...
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

each_deploy() { # [NOALL=] [ALL=] [NOSUBPROC=1] MACHINES="" DEPLOYS= COMMAND ARGS...
	[[ $MACHINES ]] && die "Invalid deploy(s): $MACHINES"
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
		active_deploys
		machine_of $DEPLOY
		[[ $QUIET ]] || say "On deploy $DEPLOY:"
		if [[ $NOSUBPROC ]]; then
			MACHINE=$R1 "$CMD" "$@"
		else
			(MACHINE=$R1 "$CMD" "$@")
		fi
	done
}

_each_deploy_with_domain() {
	if deploy_var DOMAIN; then
		local DOMAIN=$R1
		(DOMAIN=$DOMAIN "$@")
	fi
}
each_deploy_with_domain() {
	each_deploy _each_deploy_with_domain "$@"
}

each_deploy_or_machine() {
	if [[ $MM_DEPLOY ]]; then
		each_deploy "$@"
	else
		each_machine "$@"
	fi
}

each_machine_or_deploy() {
	each_deploy_or_machine "$@"
}

# machine & deploy ops -------------------------------------------------------

machine_rename() { # OLD_MACHINE NEW_MACHINE
	local OLD_MACHINE=$1
	local NEW_MACHINE=$2
	checkvars OLD_MACHINE NEW_MACHINE
	set_hostname $NEW_MACHINE
}
