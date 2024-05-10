# die harder, see https://github.com/capr/die which this extends.

# colors!

[[ $TERM ]] && {
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
LIGHTGRAY="\e[37m"
GRAY="\e[90m"
LIGHTRED="\e[91m"
LIGHTGREEN="\e[92m"
LIGHTYELLOW="\e[93m"
LIGHTBLUE="\e[94m"
LIGHTMAGENTA="\e[95m"
LIGHTCYAN="\e[96m"
WHITE="\e[97m"
ENDCOLOR="\e[0m"
}

# printing, tracing & error handling

say()       { printf "%b\n" "$*" >&2; }
sayn()      { printf "%b"   "$*" >&2; }
sayf()      { printf "$@" >&2; }
say_ln()    { printf '=%.0s\n' {1..72}; }
die()       { say "${RED}ABORT:$ENDCOLOR $*"; exit 1; }
debug()     { if [[ $DEBUG ]]; then sayn "$CYAN"; say  "$*$ENDCOLOR"; fi; }
debugn()    { if [[ $DEBUG ]]; then sayn "$CYAN"; sayn "$*$ENDCOLOR"; fi; }
run()       { debug "\nEXEC: $*"; "$@"; local ret=$?; [[ $ret == 0 ]] || debug "[$ret]"; return $ret; }
must()      { debug "\nMUST: $*"; "$@"; local ret=$?; [[ $ret == 0 ]] || die "$* [$ret]"; }
dry()       { if [[ $DRY ]]; then say "DRY: $*"; else "$@"; fi; }
nag()       { [[ $VERBOSE ]] || return 0; say "$@"; }

_ON_EXIT=
_on_exit() {
	eval $_ON_EXIT
}
trap _on_exit EXIT
on_exit()  { # CMD ARGS ...
	quote_args "$@"
	_ON_EXIT+="${R1[@]}"$'\n'
}

# arg checking and sanitizing

checknosp() { # VAL [ERROR...]
	local val="$1"; shift
	[[ "${val}" =~ ( |\') ]] && die "${FUNCNAME[1]}: contains spaces: '$val'"
	[[ "${val}" ]] || die "${FUNCNAME[1]}: $@"
}

checkvars() { # VARNAME1[-] ...
	local var
	for var in $@; do
		if [[ ${var::-1}- == $var ]]; then # spaces allowed
			var=${var::-1}
			[[ ${!var} ]] || die "${FUNCNAME[1]}: $var required"
		else
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

quote_vars() { # VAR1 ...
	R1=()
	local var
	local s
	for var in "$@"; do
		printf -v s "%q=%q\n" "$var" "${!var}"
		R1+=("$s")
	done
}

# enhanced sudo that can:
#  1. inherit a list of vars.
#  2. execute a function from the current script, or an entire script.
#  3. include additional function definitions needed to run said function.
#  4. pass args to said function.
run_as() { # VARS="VAR1 ..." FUNCS="FUNC1 ..." USER "SCRIPT" ARG1 ...
	local user=$1 script=$2; shift 2
	checkvars user script-
	quote_args "$@"; local args="${R1[*]}"
	local vars=$(declare -p DEBUG VERBOSE $VARS 2>/dev/null)
	[[ $FUNCS ]] && local funcs=$(declare -f $FUNCS)
	sudo -u "$user" bash -s <<< "
$vars
$funcs
$script $args
"
}

# reflection

functions_with_prefix() { # PREFIX
	local prefix="$1"
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
