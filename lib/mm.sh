# mm lib: functions reading var/machines and var/deploys on the mm machine.

mm_update() {
	git_clone_for root git@github.com:allegory-software/many-machines2 /opt/mm master mm
	# install globally
	must ln -sf /opt/mm/mm      /usr/bin/mm
	must ln -sf /opt/mm/lib/all /usr/bin/mmlib
}

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

active_machines() {
	R1=
	local MACHINE
	for MACHINE in `ls -1 var/machines`; do
		[ "$INACTIVE" != "" -o -f "var/machines/$MACHINE/active" ] && R1+=" $MACHINE"
	done
}

each_machine() { # [NOT_ALL=] [ALL=] MACHINES= DEPLOYS= COMMAND ARGS...
	declare -A mm
	local M D
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
		[[ $NOT_ALL  && ! $ALL ]] && die "MACHINE(s) required"
		active_machines
		MACHINES="$R1"
	fi
	[[ ! $QUIET && ${#mm[@]} == 1 ]] && QUIET=1
	local CMD="$1"; shift
	local MACHINE
	for MACHINE in $MACHINES; do
		[ "$QUIET" ] || say "On machine $MACHINE:"
		("$CMD" "$@")
	done
}

_each_machine_list() { # MACHINE= LIST
	printf "%-10s %s\n" $MACHINE "$(ssh_script "machine_list_$1" 2>&1)"
}
each_machine_list() { # LIST
	local LIST="$1"
	checkvars LIST
	printf "%-10s %s\n" "MACHINE" "$(machine_list_header_${LIST})"
	QUIET=1 each_machine _each_machine_list $LIST
}

custom_list_get_values() { # FIELD1 ...
	local FIELD
	for FIELD in $*; do
		if declare -f example_function > /dev/null; then
			get_${FIELD}
		else
			echo "${!FIELD}"
		fi
	done
}
_each_machine_custom_list() { # FMT FIELD1 ...
	local FMT="$1"; shift
	local VALS
	(
	if VALS="$(ssh_script_machine "custom_list_get_values $*" 2>&1)"; then
		local IFS0="$IFS"; IFS=$'\n'; printf "%-10s $FMT\n" $MACHINE $VALS; IFS="$IFS0"
	else
		printf "%-10s %s\n" $MACHINE "$VALS"
	fi
	) &
	wait
}
each_machine_custom_list() { # FMT FIELD1 ...
	local FMT="$1"; shift
	printf "%-10s $FMT\n" MACHINE $*
	QUIET=1 each_machine _each_machine_custom_list "$FMT" $*
}

_each_deploy_custom_list() { # FMT FIELD1 ...
	local FMT="$1"; shift
	local VALS
	(
	if VALS="$(ssh_script_deploy "custom_list_get_values $*" 2>&1)"; then
		local IFS0="$IFS"; IFS=$'\n'; printf "%-10s %-10s $FMT\n" $MACHINE $DEPLOY $VALS; IFS="$IFS0"
	else
		printf "%-10s %-10s %s\n" $MACHINE $DEPLOY "$VALS"
	fi
	) &
	wait
}
each_deploy_custom_list() { # FMT FIELD1 ...
	local FMT="$1"; shift
	printf "%-10s %-10s $FMT\n" MACHINE DEPLOY $*
	QUIET=1 each_deploy _each_deploy_custom_list "$FMT" $*
}

machine_vars() { # MACHINE|DEPLOY
	machine_of "$1"; local MACHINE=$R1
	cat_all_varfiles var/machines/$MACHINE/vars
}

deploy_var() { # DPELOY VAR
	local DEPLOY="$1"
	local VAR="$2"
	checkvars DEPLOY VAR
	cat_varfile var/deploys/$DEPLOY $VAR
}

deploy_vars() { # DEPLOY
	local DEPLOY="$1"
	machine_of_deploy "$DEPLOY"; local MACHINE=$R1
	cat_all_varfiles var/deploys/$DEPLOY
}

active_deploys() {
	R1=
	local DEPLOY
	for DEPLOY in `ls -1 var/deploys`; do
		[[ "$INACTIVE" != "" || -f var/deploys/$DEPLOY/active ]] && R1+=" $DEPLOY"
	done
}

each_deploy() { # [NOT_ALL=] [ALL=] MACHINES="" DEPLOYS= COMMAND ARGS...
	[[ $MACHINES ]] && die "Invalid deploy(s): $MACHINES"
	if [[ $DEPLOYS ]]; then
		for DEPLOY in $DEPLOYS; do
			check_deploy $DEPLOY
		done
	else
		[[ $NOT_ALL && ! $ALL ]] && die "DEPLOY(s) required"
		active_deploys
		DEPLOYS="$R1"
	fi
	local CMD="$1"; shift
	for DEPLOY in $DEPLOYS; do
		machine_of $DEPLOY
		[ "$QUIET" ] || say "On deploy $DEPLOY:"
		(MACHINE=$R1 "$CMD" "$@")
	done
}

_each_deploy_with_domain() {
	if deploy_var $DEPLOY DOMAIN; then
		local DOMAIN=$R1
		(DOMAIN=$DOMAIN "$@")
	fi
}
each_deploy_with_domain() {
	each_deploy _each_deploy_with_domain "$@"
}

_each_deploy_list() { # DEPLOY= LIST
	printf "%-10s %-10s %s\n" $MACHINE $DEPLOY "$(ssh_script_deploy "deploy_list_$1" 2>&1)"
}
each_deploy_list() { # LIST
	local LIST="$1"
	checkvars LIST
	printf "%-10s %-10s %s\n" "MACHINE" "DEPLOY" "$(deploy_list_header_${LIST})"
	QUIET=1 each_deploy _each_deploy_list $LIST
}
