# die harder, see https://github.com/capr/die which this extends.

export INDENT
SAY_NL=

say()       { echo "$@" >&2; }
say-line()  { printf '=%.0s\n' {1..72}; }
die()       { say -n "ABORT: "; say "$@"; exit 1; }
debug()     { if [ "$DEBUG" ]; then say "$@"; fi; }
run()       { debug -n "EXEC: $@ "; "$@"; local ret=$?; debug "[$ret]"; return $ret; }
must()      { debug -n "MUST: $@ "; "$@"; local ret=$?; debug "[$ret]"; [ $ret == 0 ] || die "$@ [$ret]"; }
dry()       { if [ "$DRY" ]; then say "DRY: $@"; else "$@"; fi; }

quote_args() { # ARGS...
	# must use an array because we need to quote each arg individually,
	# and not concat and expand them to pass them along, becaue even
	# when quoted they may contain spaces and would expand incorrectly.
	R1=()
	for arg in "$@"; do
		R1+=("$(printf "%q" "$arg")")
	done
}

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
	[[ "${val}" =~ ( |\') ]] && die "${FUNCNAME[1]}: contains spaces: '$val'"
	[[ "${val}" ]] || die "${FUNCNAME[1]}: $@"
}

checkvars() { # VARNAME1[-] ...
	local var
	for var in $@; do
		if [ "${var::-1}-" == "${var}" ]; then # spaces allowed
			var="${var::-1}"
			[ "${!var}" ] || die "${FUNCNAME[1]}: $var required"
		else
			[ "${!var}" ] || die "${FUNCNAME[1]}: $var required"
			[[ "${!var}" =~ ( |\') ]] && die "${FUNCNAME[1]}: $var contains spaces"
		fi
	done
	return 0
}

trim() { # VARNAME
	read -rd '' $1 <<<"${!1}"
}
