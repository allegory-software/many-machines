# remote listings with configurable field lists

_md_ssh_list() {
	local FUNC=$1 FMT=$2 FIELDS=$3 FMT_VALS=$4; shift 4
	[[ $FMT_VALS ]] || FMT_VALS=$FMT
	local VALS
	(
	if VALS=$(VARS="FIELDS $VARS" md_ssh_script $FUNC "$@"); then
		local IFS0="$IFS"; IFS=$'\n'
		[[ $VALS ]] && printf "%-10s %-10s $FMT_VALS\n" $VALS
		IFS="$IFS0"
	else
		printf "%-10s %-10s %s\n" "$MACHINE" "${DEPLOY:-*}" "$VALS"
	fi
	) &
	wait
}
md_ssh_list() { # LIST_FUNC FMT "FIELD1 ..." FMT_VALS LIST_FUNC_ARGS...
	local FUNC=$1 FMT=$2 FIELDS=$3
	checkvars FUNC FMT- FIELDS-
	printf "${WHITE}%-10s %-10s $FMT$ENDCOLOR\n" MACHINE DEPLOY $FIELDS
	QUIET=1 each_md _md_ssh_list "$@"
}

# listings with configurable field lists -------------------------------------

_custom_list_get_values() { # "FIELD1 ..."
	local FIELD
	for FIELD in $1; do
		FIELD=$(printf "%s" "$FIELD" | sed -E 's/\x1B\[[0-9;]*m//g')
		local VAL
		if declare -f get_${FIELD} > /dev/null; then
			VAL=`get_${FIELD}`
		else
			VAL=${!FIELD}
		fi
		VAL=${VAL:- } # can't echo an empty line, it will get skipped when line-splitting.
		local MIN_FIELD=MIN_$FIELD
		local MIN=${!MIN_FIELD}
		local VALN=${VAL//[^0-9.]/}
		#[[ $MIN ]] && awk "{if ($VALN < $MIN) exit 0; else exit 1}" && VAL=${RED}$VAL$ENDCOLOR || VAL=${LIGHTGRAY}$VAL$ENDCOLOR
		printf "%s\n" "$VAL"
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
