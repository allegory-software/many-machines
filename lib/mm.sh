# mm lib: functions reading var/machines and var/deploys.

mm_update() {
	git_clone_for root git@github.com:allegory-software/many-machines2 /opt/mm master mm
	# install globally
	must ln -sf /opt/mm/mm      /usr/bin/mm
	must ln -sf /opt/mm/lib/all /usr/bin/mmlib
}

# machines database ----------------------------------------------------------

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

each_machine() { # [MACHINES] COMMAND ...
	local MDS="$1"; shift
	local MACHINES
	local DEPLOYS
	if [ "$MDS" ]; then
		local MD
		for MD in $MDS; do
			ip_of $MD
			DEPLOYS+=" $R3"
			MACHINES+=" $R2"
		done
		[[ ! $QUIET && $MDS != *" "* ]] && QUIET=1
	else
		active_machines
		MACHINES="$R1"
	fi
	local CMD="$1"; shift
	for MACHINE in $MACHINES; do
		[ "$QUIET" ] || say "On machine $MACHINE:"
		(DEPLOYS="$DEPLOYS" "$CMD" "$MACHINE" "$@")
	done
}

_machine_list() { # MACHINE LIST
	printf "%-10s %s\n" $1 "$(ssh_script $MACHINE "machine_list_$2" 2>&1)"
}
each_machine_list() { # [MACHINES] LIST_NAME
	local LIST="$2"
	checkvars LIST
	printf "%-10s %s\n" MACHINE "$(machine_list_${LIST}_header)"
	QUIET=1 each_machine "$1" _machine_list $LIST
}

# deployments database -------------------------------------------------------

deploy_vars() {
	machine_of_deploy "$1"; local MACHINE=$R1
	cat_all_varfiles var/deploys/$1
	R1+=("MACHINE=$MACHINE"$'\n')
}

active_deploys() {
	R1=
	local DEPLOY
	for DEPLOY in `ls -1 var/deploys`; do
		[[ "$INACTIVE" != "" || -f var/deploys/$DEPLOY/active ]] && R1+=" $DEPLOY"
	done
}

each_deploy() { # [DEPLOYS] COMMAND ...
	local DEPLOYS="$1"; shift
	if [ "$DEPLOYS" ]; then
		local DEPLOY
		for DEPLOY in $DEPLOYS; do
			check_deploy $DEPLOY
		done
	else
		active_deploys
		DEPLOYS="$R1"
	fi
	local CMD="$1"; shift
	for DEPLOY in $DEPLOYS; do
		[ "$QUIET" ] || say "On deploy $DEPLOY:"
		("$CMD" "$DEPLOY" "$@")
	done
}
