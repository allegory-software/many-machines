#!/bin/bash
cd "$(dirname "$0")" || exit 1
CMD_DIR=c-mm
CMD="$1"
[ "$CMD" ] || {
	ls -1 $CMD_DIR
	exit
}
shift

$CMD_DIR/$CMD "$@"
