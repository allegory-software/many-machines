#!/bin/bash
cd /opt/mm || exit 1

DEPLOYS=
MACHINES=
while [[ $# > 0 ]]; do
	if [[ -f cmd/$1 ]]; then
		CMD=$1; shift; cmd/$CMD "$@"
		exit
	elif [[ -d var/deploys/$1 ]]; then
		DEPLOYS+=" $1"; shift
	elif [[ -d var/machines/$1 ]]; then
		MACHINES+=" $1"; shift
	else
		echo "Usage: mm [DEPLOY1|MACHINE1 ...] [COMMAND ARGS...]" >&2
		exit 1
	fi
done

if [[ $DEPLOYS || $MACHINES ]]; then
	[[ $DEPLOYS  ]] && printf "DEPLOYS  : %s\n" "$DEPLOYS"
	[[ $MACHINES ]] && printf "MACHINES : %s\n" "$MACHINES"
	exit
fi

for CMD in `ls -1 cmd`; do
	HELP="$(head -2 "cmd/$CMD" | tail -1)"
	printf "mm %-20s %s\n" "$CMD" "$HELP"
done
