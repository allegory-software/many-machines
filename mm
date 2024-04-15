#!/bin/bash
cd /opt/mm || exit 1
CMD_DIR=cmd
CMD="$1"
[ "$CMD" ] || {
	for CMD in `ls -1 $CMD_DIR`; do
		HELP="$(head -2 "$CMD_DIR/$CMD" | tail -1)"
		printf "mm %-20s %s\n" "$CMD" "$HELP"
	done
	exit
}
shift

$CMD_DIR/$CMD "$@"
