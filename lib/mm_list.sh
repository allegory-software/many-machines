# remote listings with configurable field lists

_machine_ssh_list() {
	local FUNC=$1 FMT=$2 FIELDS=$3; shift 3
	local VALS
	(
	if VALS=$(VARS=FIELDS ssh_script_machine $FUNC "$@"); then
		local IFS0="$IFS"; IFS=$'\n'
		printf "%-10s $FMT\n" $VALS
		IFS="$IFS0"
	else
		printf "%-10s %s\n" $MACHINE "$VALS"
	fi
	) &
	wait
}
each_machine_ssh_list() { # LIST_FUNC FMT "FIELD1 ..." LIST_FUNC_ARGS...
	local FUNC=$1 FMT=$2 FIELDS=$3
	checkvars FUNC FMT- FIELDS-
	printf "%-10s $FMT\n" MACHINE $FIELDS
	QUIET=1 each_machine _machine_ssh_list "$@"
}

_deploy_ssh_list() {
	local FUNC=$1 FMT=$2 FIELDS=$3; shift 3
	local VALS
	(
	if VALS=$(VARS="MM_DEPLOY FIELDS" ssh_script_deploy $FUNC "$@"); then
		local IFS0="$IFS"; IFS=$'\n'
		printf "%-10s %-10s $FMT\n" $VALS
		IFS="$IFS0"
	else
		printf "%-10s %-10s %s\n" $MACHINE $DEPLOY "$VALS"
	fi
	) &
	wait
}
each_deploy_ssh_list() { # LIST_FUNC FMT "FIELD1 ..." LIST_FUNC_ARGS...
	local FUNC=$1 FMT=$2 FIELDS=$3
	checkvars FUNC FMT- FIELDS-
	printf "%-10s %-10s $FMT\n" MACHINE DEPLOY $FIELDS
	QUIET=1 each_deploy _deploy_ssh_list "$@"
}

each_md_ssh_list() {
	if [[ $MM_DEPLOY ]]; then
		each_deploy_ssh_list "$@"
	else
		each_machine_ssh_list "$@"
	fi
}

# listings with configurable field lists -------------------------------------

_custom_list_get_values() { # "FIELD1 ..."
	local FIELD
	for FIELD in $1; do
		local VAL
		if declare -f get_${FIELD} > /dev/null; then
			VAL=`get_${FIELD}`
		else
			VAL=${!FIELD}
		fi
		VAL=${VAL:- } # can't echo an empty line, it will get skipped when line-splitting.
		#local MIN=${!MIN_$FIELD}
		#[[ $MIN ]] && ((VAL < MIN)) && continue
		printf "%s\n" "$VAL"
	done
}
_machine_custom_list() {
	echo $MACHINE
	_custom_list_get_values "$FIELDS"
}
each_machine_custom_list() { # FMT "FIELD1 ..."
	each_machine_ssh_list _machine_custom_list "$@"
}

_deploy_custom_list() {
	echo $MACHINE
	echo $DEPLOY
	_custom_list_get_values "$FIELDS"
}
each_deploy_custom_list() { # FMT "FIELD1 ..."
	each_deploy_ssh_list _deploy_custom_list "$@"
}
