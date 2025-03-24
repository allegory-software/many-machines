#!/bin/bash
cd /root/mm || exit 1

export DEPLOYS
export MACHINES

set -f # disable globbing
set -o pipefail

. lib/die.sh

on_exit sayn $ENDCOLOR

[[ $UID == 0 ]] || die "Must be root."

usage() {
	say
	say "Usage: ${WHITE}[MACHINES=\"MACHINE1 ...\"] [DEPLOYS=\"DEPLOY1 ...\"] mm [DEPLOY1|MACHINE1 ...] COMMAND ARGS...$ENDCOLOR"
	say "Usage: ${WHITE}[DEPLOYS=\"DEPLOY1 ...\"] mmd DEPLOY1 ... COMMAND ARGS...$ENDCOLOR"
	say "Usage: ${WHITE}mm [--]help|-?|-h [SECTION]$ENDCOLOR"
	say "Usage: ${WHITE}mm COMMAND [--]help|-?|-h $ENDCOLOR"
	say
}

cmd_metadata() { # CMD= -> SECTION= ARGS= DESCR=
	# read the 2nd line of the cmd file; faster than `head -2 | tail -1`.
	local s
	exec 3< cmd/$CMD
	read s <&3
	read s <&3
	exec 3<&-
	# split line into parts.
	IFS=";" read -r SECTION ARGS DESCR <<< "$s"
	trim SECTION; trim ARGS; trim DESCR
	SECTION=${SECTION//\#[[:space:]]/}
}

main() {
declare -A mm # mm[MACHINE]=1
declare -A dm # dm[DEPLOY]=1
while [[ $# > 0 ]]; do
	if [[ -f cmd/$1 ]]; then
		local CMD=$1; shift
		if [[ $# == 0 ]]; then # check if cmd has non-optional args
			local SECTION ARGS DESCR; cmd_metadata
			[[ ! $ARGS || $ARGS =~ ^\[.*\]$ ]] \
				|| die "Usage: ${WHITE}mm $CMD $ARGS$ENDCOLOR $GREEN# $DESCR$ENDCOLOR"
		fi
		if [[ $# == 1 && ( $1 == help || $1 == "--help" || $1 == "-?" || $1 == "-h" ) ]]; then # special arg 'help' treated here
			local SECTION ARGS DESCR; cmd_metadata
			say "Usage: ${WHITE}mm $CMD $ARGS$ENDCOLOR $GREEN# $DESCR$ENDCOLOR"
			exit
		fi
		run cmd/$CMD "$@"
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
	elif [[ $1 == help ]]; then
		HELP=1
		shift
		break
	else
		say "${RED}ABORT:$ENDCOLOR Invalid DEPLOY, MACHINE or COMMAND: $WHITE$1$ENDCOLOR"
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
declare -A cmds
for CMD in `ls -1 cmd`; do
	local SECTION ARGS DESCR; cmd_metadata
	# add help line to its section.
	printf -v s "mm ${WHITE}%-20s${ENDCOLOR} %s\n" "${CMD} $ARGS" "$DESCR"
	help[$SECTION]+="$s"
	cmds[$SECTION]+="$CMD "
done

local s=$(printf "%s\n" "${!help[@]}" | sort)
local SECTION
IFS=$'\n'
for SECTION in $s; do
	if [[ $HELP ]]; then
		[[ ! $1 || ${SECTION,,} == ${1,,} ]] && {
			say "$GREEN${SECTION}$ENDCOLOR"
			say "${help[$SECTION]}"
		}
	else
		sayf "%-26s %s\n" "$GREEN${SECTION}$ENDCOLOR" "${cmds[$SECTION]}"
	fi
done
say
}

main "$@"
