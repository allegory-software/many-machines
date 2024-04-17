#!/bin/bash
cd /opt/mm || exit 1

export DEPLOYS
export MACHINES

usage() {
	echo "Usage: mm [DEPLOY1|MACHINE1 ...] COMMAND ARGS..." >&2
}

declare -A mm # mm[MACHINE]=1
declare -A dm # dm[DEPLOY]=1
while [[ $# > 0 ]]; do
	if [[ -f cmd/$1 ]]; then
		CMD=$1; shift; cmd/$CMD "$@"
		exit
	elif [[ -d var/deploys/$1 ]]; then
		[[ ! ${dm[$1]} ]] && { DEPLOYS+=" $1"; dm[$1]=1; }
		shift
	elif [[ -d var/machines/$1 ]]; then
		[[ ! ${mm[$1]} ]] && { MACHINES+=" $1"; mm[$1]=1; }
		shift
	else
		usage
		exit 1
	fi
done

if [[ $DEPLOYS || $MACHINES ]]; then
	cmd/ssh
	exit
fi

usage
for CMD in `ls -1 cmd`; do
	HELP="$(head -2 "cmd/$CMD" | tail -1)"
	printf "mm %-20s %s\n" "$CMD" "$HELP" >&2
done
