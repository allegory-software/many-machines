# die harder, see https://github.com/capr/die

export INDENT
SAY_NL=

indent()    { INDENT="$INDENT  "; }
outdent()   { INDENT="${INDENT:0:${#INDENT}-2}"; }
indent-stdin() { sed "s/^/$INDENT/"; }
say()       { [ "$SAY_NL" ] && echo -n "${INDENT}"; echo "$@" >&2; [ "$1" == "-n" ] && [ "$1" == -n ] && SAY_NL= || SAY_NL=1; }
die()       { echo -n "${INDENT}ABORT: " >&2; echo "$@" >&2; exit 1; }
debug()     { if [ "$DEBUG" ]; then echo    "${INDENT}$@" >&2; fi; }
debug-n()   { if [ "$DEBUG" ]; then echo -n "${INDENT}$@" >&2; fi; }
run()       { debug -n "${INDENT}EXEC: $@ "; "$@"; local ret=$?; debug "[$ret]"; return $ret; }
must()      { debug -n "${INDENT}MUST: $@ "; "$@"; local ret=$?; debug "[$ret]"; [ $ret == 0 ] || die "${INDENT}$@ [$ret]"; }

# enhanced sudo that can:
#  1. inherit a list of vars.
#  2. run a local function. including multiple function definitions.
run_as() { # user cmd
	local user="$1"; shift
	local cmd="$1"; shift
	local vars="$(for v in $VARS; do printf '%q=%q ' "$v" "${!v}"; done;)"
	local decl="$(declare -f $FUNCS $cmd)"
	if [ "$decl" ]; then
		echo "$decl; $cmd" | eval sudo -u "$user" $vars bash -s
	else
		eval sudo -u "$user" $vars "$cmd" "$@"
	fi
}

checknosp() { # VAL [ERROR...]
	local val="$1"; shift
	[[ "${val}" =~ ( |\') ]] && die "${FUNCNAME[1]}: contains spaces: $val"
	[ "${val}" ] || die "${FUNCNAME[1]}: $@"
}

checkvar() { # NAME[-] [ERROR...]
	local var="$1"; shift
	if [ "${var::-1}-" == "${var}" ]; then # spaces allowed
		var="${var::-1}"
		[ "${!var}" ] && return 0
	else
		[[ "${!var}" =~ ( |\') ]] && die "${FUNCNAME[1]}: \$$var contains spaces"
		[ "${!var}" ] && return 0
	fi
	local err="$@"; [ "$err" ] || err="required"
	die "${FUNCNAME[1]}: \$$var: $err"
}

checkvars() { # NAME1[-] NAME2 ...
	local var
	for var in $@; do
		if [ "${var::-1}-" == "${var}" ]; then # spaces allowed
			var="${var::-1}"
			[ "${!var}" ] || die "${FUNCNAME[1]}: \$$var required"
		else
			[ "${!var}" ] || die "${FUNCNAME[1]}: \$$var required"
			[[ "${!var}" =~ ( |\') ]] && die "${FUNCNAME[1]}: \$$var contains spaces"
		fi
	done
	return 0
}

checkfile() {
    [ -f "$1" ] || die "File not found: $1"
    R1="$1"
}
