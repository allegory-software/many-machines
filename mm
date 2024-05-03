#!/bin/bash
cd /opt/mm || exit 1

set -f # disable globbing
set -o pipefail

export DEPLOYS
export MACHINES

. lib/die.sh

usage() {
	say
	say "Usage: mm [DEPLOY1|MACHINE1 ...] COMMAND ARGS..."
	say
}

main() {
declare -A mm # mm[MACHINE]=1
declare -A dm # dm[DEPLOY]=1
while [[ $# > 0 ]]; do
	if [[ -f cmd/$1 ]]; then
		local CMD=$1; shift; cmd/$CMD "$@"
		exit
	elif [[ -d var/deploys/$1 ]]; then
		[[ ! ${dm[$1]} ]] && { DEPLOYS+=" $1"; dm[$1]=1; }
		shift
	elif [[ -d var/machines/$1 ]]; then
		[[ ! ${mm[$1]} ]] && { MACHINES+=" $1"; mm[$1]=1; }
		shift
	elif [[ $1 == -v ]]; then
		export VERBOSE=1
		shift
	else
		say "Invalid DEPLOY, MACHINE or COMMAND: $1"
		usage
		exit 1
	fi
done

# no command given but machines and/or deploys given, drop to shell on each.
if [[ $DEPLOYS || $MACHINES ]]; then
	cmd/ssh
	exit
fi

# no args at all, show available commands.
usage
declare -A help
for CMD in `ls -1 cmd`; do
	# read the 2nd line of file; faster than `head -2 | tail -1`.
	local s
	exec 3< cmd/$CMD
	read s <&3
	read s <&3
	exec 3<&-
	# split line into parts.
	local SECTION ARGS DESCR
	IFS=";" read -r SECTION ARGS DESCR <<< "$s"
	trim SECTION; trim ARGS; trim DESCR
	# add help line to its section.
	printf -v s "mm ${WHITE}%-20s${ENDCOLOR} %s\n" "${CMD} $ARGS" "$DESCR"
	help[$SECTION]+="$s"
done

local s=$(printf "%s\n" "${!help[@]}" | sort)
local SECTION
IFS=$'\n'
for SECTION in $s; do
	printf "${GREEN}%s${ENDCOLOR}\n" "$SECTION" >&2
	printf "%s\n" "${help[$SECTION]}" >&2
done
}

main "$@"
