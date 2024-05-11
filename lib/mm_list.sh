# remote listings with configurable field lists

_md_ssh_list() {
	local FUNC=$1 FMT=$2 FIELDS=$3; shift 3
	local VALS
	(
	if VALS=$(VARS="FIELDS" md_ssh_script $FUNC "$@"); then
		local IFS0="$IFS"; IFS=$'\n'
		printf "%-10b %-10b $FMT\n" $VALS
		IFS="$IFS0"
	else
		printf "%-10b %-10b %b\n" "$MACHINE" "${DEPLOY:-*}" "$VALS"
	fi
	) &
	wait
}
md_ssh_list() { # LIST_FUNC FMT "FIELD1 ..." LIST_FUNC_ARGS...
	local FUNC=$1 FMT=$2 FIELDS=$3
	checkvars FUNC FMT- FIELDS-
	printf "${WHITE}%-10b %-10b $FMT$ENDCOLOR\n" MACHINE DEPLOY $FIELDS
	QUIET=1 each_md _md_ssh_list "$@"
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
		printf "%b\n" "$VAL"
	done
}
_md_custom_list() {
	echo $MACHINE
	echo ${DEPLOY:-*}
	_custom_list_get_values "$FIELDS"
}
md_custom_list() { # FMT "FIELD1 ..."
	md_ssh_list _md_custom_list "$@"
}
m_custom_list() { MM_DEPLOY=  md_custom_list "$@"; }
d_custom_list() { MM_DEPLOY=1 md_custom_list "$@"; }
