# die harder, see https://github.com/capr/die which this extends.

# colors!

[[ $TERM ]] && {

RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
MAGENTA=$'\e[35m'
CYAN=$'\e[36m'
LIGHTGRAY=$'\e[37m'
GRAY=$'\e[90m'
LIGHTRED=$'\e[91m'
LIGHTGREEN=$'\e[92m'
LIGHTYELLOW=$'\e[93m'
LIGHTBLUE=$'\e[94m'
LIGHTMAGENTA=$'\e[95m'
LIGHTCYAN=$'\e[96m'
WHITE=$'\e[97m'
BLACK=$'\e[30m'

BG_RED=$'\e[41m'
BG_GREEN=$'\e[42m'
BG_YELLOW=$'\e[43m'
BG_BLUE=$'\e[44m'
BG_MAGENTA=$'\e[45m'
BG_CYAN=$'\e[46m'

# NOTE: these are one byte longer, so they mess the printf widths.
BG_BRIGHTBLACK=$'\e[100m'
BG_BRIGHTRED=$'\e[101m'
BG_BRIGHTGREEN=$'\e[102m'
BG_BRIGHTYELLOW=$'\e[103m'
BG_BRIGHTBLUE=$'\e[104m'
BG_BRIGHTMAGENTA=$'\e[105m'
BG_BRIGHTCYAN=$'\e[106m'
BG_BRIGHTWHITE=$'\e[107m'

BG_WHITE=$'\e[47m'
BG_BLACK=$'\e[40m'

ENDCOLOR=$'\e[0m'

[[ $MM_WHITE_BG ]] && {
	BLACK_REAL="$BLACK"
	WHITE_REAL="$WHITE"
	WHITE="$BLACK_REAL"
	BLACK="$WHITE_REAL"
}

}

# printing, tracing & error handling

say()       { printf "%s\n" "$*" >&2; }
sayn()      { printf "%s${DEBUG:+\n}" "$*" >&2; }
sayf()      { printf "$@" >&2; }
die()       { say "${RED}ABORT:$ENDCOLOR $*"; exit 1; }
debug()     { if [[ $DEBUG ]]; then printf "%s" "$CYAN" >&2; printf "%s$ENDCOLOR\n" "$*" >&2; fi; }
debugn()    { if [[ $DEBUG ]]; then printf "%s" "$CYAN" >&2; printf "%s$ENDCOLOR"   "$*" >&2; fi; }
run()       { debug "EXEC: $*"; "$@"; local ret=$?; [[ $ret == 0 ]] || debug "[$ret]"; return $ret; }
must()      { debug "MUST: $*"; "$@"; local ret=$?; [[ $ret == 0 ]] || die "$* [$ret]"; }
dry()       { if [[ $DRY ]]; then say "DRY: $*"; else "$@"; fi; }
nag()       { [[ $VERBOSE ]] || return 0; say "$@"; }

on_exit() { # CMD ARGS ...
	local s=`trap -p EXIT`; s=${s:9:-7}
	quote_args "$@"
	trap "$s
${R1[*]}
" EXIT
}

# arg checking and sanitizing

checknosp() { # VAL [ERROR...]
	local val="$1"; shift
	[[ "${val}" =~ ( |\') ]] && die "${FUNCNAME[1]}: contains spaces: '$val'"
	[[ "${val}" ]] || die "${FUNCNAME[1]}: $@"
}

checkvars() { # VARNAME1[-|?] ...
	local var
	for var in $@; do
		if [[ ${var::-1}? == $var ]]; then # optional and spaces not allowed
			var=${var::-1}
			[[ ${!var} ]] || continue
			[[ ${!var} =~ ( |\') ]] && die "${FUNCNAME[1]}: $var contains spaces"
		elif [[ ${var::-1}- == $var ]]; then # required but spaces allowed
			var=${var::-1}
			[[ ${!var} ]] || die "${FUNCNAME[1]}: $var required"
		else # required and spaces not allowed
			[[ ${!var} ]] || die "${FUNCNAME[1]}: $var required"
			[[ ${!var} =~ ( |\') ]] && die "${FUNCNAME[1]}: $var contains spaces"
		fi
	done
	return 0
}

checkvar_in() { # VARNAME VAL1 ...
	local var=$1; shift
	local val=${!var}
	local v; for v in "$@"; do
		[[ $val == $v ]] && return 0
	done
	local s="$*"; s=${s// /|}
	die "${FUNCNAME[1]}: $var: invalid: $val, expected: $s"
}

# quoting args, vars and bash code for passing scripts through sudo and ssh.

quote_args() { # ARGS...
	# must use an array because we need to quote each arg individually,
	# and not concat and expand them to pass them along, becaue even
	# when quoted they may contain spaces and would expand incorrectly.
	R1=()
	local arg
	local s
	for arg in "$@"; do
		printf -v s "%q" "$arg"
		R1+=("$s")
	done
}

# enhanced sudo that can:
#  1. inherit a list of vars.
#  2. execute a function from the current script, or an entire script.
#  3. include additional function definitions needed to run said function.
#  4. pass args to said function.
#  5. stdin is piped in to the function.
run_as() { # VARS="VAR1 ..." FUNCS="FUNC1 ..." USER "SCRIPT" ARG1 ...
	local user=$1 script=$2; shift 2
	checkvars user script-
	quote_args "$@"; local args="${R1[*]}"
	local vars=$(declare -p DEBUG VERBOSE $VARS 2>/dev/null)
	[[ $FUNCS ]] && local funcs=$(declare -f $FUNCS)
	debug "-------------------------------------------------------"
	debug "run_as $USER:"
	debug "-------------------------------------------------------"
	debug "$vars"
	debug "$funcs"
	debug "$script"
	debug "-------------------------------------------------------"
	run sudo -u "$user" bash -s <<< "
$vars
$funcs
$script $args
exit"
}

# reflection

functions_with_prefix() { # PREFIX
	local prefix=$1
	R1=
	for func_name in $(declare -F | awk '{print $3}'); do
		if [[ $func_name == "$prefix"* ]]; then
			R1+=" ${func_name#$prefix}"
		fi
	done
}

# data manipulation

trim() { # VARNAME
	read -rd '' $1 <<<"${!1}"
	return 0
}

to_keys() { # MAP KEY1 ...
	local -n map=$1; shift
	local s; for s in "$@"; do
		map[$s]=1
	done
}

array_reverse() {
	local i
	R1=()
	for ((i=len-1; i>=0; i--)); do
		R1+=("${1[i]}")
	done
}

# formatting

timeago() { # TIME
	local t=$1
	local now=`date +%s`
	local d=$((now - t))
	if   ((d < 2 * 60           )); then R1="$d seconds ago"
	elif ((d < 2 * 60*60        )); then R1="$(( d / (60) )) minutes ago"
	elif ((d < 2 * 60*60*24     )); then R1="$(( d / (60*60) )) hours ago"
	elif ((d < 2 * 60*60*24*30  )); then R1="$(( d / (60*60*24) )) days ago"
	elif ((d < 2 * 60*60*24*365 )); then R1="$(( d / (60*60*24*30) )) months ago"
	else                                 R1="$(( d / (60*60*24*365) )) years ago"
	fi
}

kbytes() { # BYTES
	R1=`numfmt --to=iec <<<"$1"`
}
