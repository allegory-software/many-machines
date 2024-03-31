pushd() { command pushd "$@" > /dev/null; }
popd()  { command popd  "$@" > /dev/null; }

check_abs_filepath() {
	[ "${1:0:1}" == "/" ] || die "path not absolute: $1"
	[ "${1: -1}" == "/" ] && die "path ends in slash: $1"
}

rm_dir() { # DIR
	local dir="$1"
	checkvars dir
	check_abs_filepath "$dir"
	say -n "Removing dir $dir ... "
	[ "$DRY" ] || must rm -rf "$dir"
	say OK
}

rm_file() { # FILE
	local file="$1"
	checkvars file
	check_abs_filepath "$file"
	say -n "Removing file $file ... "
	[ "$DRY" ] || must rm -f "$file"
	say OK
}

cp_file() { # SRC DST [USER]
	local src="$1"
	local dst="$2"
	local user="$3"
	checkvars src dst
	say -n "Copying file
	src: $src
	dst: $dst "
	must mkdir -p `dirname $dst`
	must cp -f $src $dst
	if [ "$user" ]; then
		checkvars user
		must chown $user:$user $dst
		must chmod 600 $dst
	fi
	say "OK"
}

sha_dir() { # DIR
	local dir="$1"
	checkvars dir
	[ -d $dir ] || die "dir not found: $dir"
	(
	set -o pipefail
	find $dir -type f -print0 | LC_ALL=C sort -z | xargs -0 sha1sum | sha1sum | cut -d' ' -f1
	) || exit $?
}

append() { # S FILE
	local s="$1"
	local file="$2"
	checkvars s- file
	say -n "Appending ${#s} bytes to file $file ... "
	debug -n "MUST: append \"$s\" $file "
	if [ "$DRY" ] || printf "%s" "$s" >> "$file"; then
		debug "[$?]"
	else
		die "append $file [$?]"
	fi
	say OK
}

save() { # S FILE [USER]
	local s="$1"
	local file="$2"
	local user="$3"
	checkvars s- file
	say -n "Saving ${#s} bytes to file $file ... "
	debug -n "MUST: save \"$s\" $file "
	if [ "$DRY" ] || printf "%s" "$s" > "$file"; then
		debug "[$?]"
	else
		die "save $file [$?]"
	fi
	if [ "$user" ]; then
		checkvars user
		must chown $user:$user $file
		must chmod 600 $file
	fi
	say OK
}

replace_lines() { # REGEX S FILE
	local regex="$1"
	local s="$2"
	local file="$3"
	checkvars regex- s- file
	say "Replacing line containing $regex to $s in file $file ... "; indent
	local s="$(cat "$file")" || die "cat $file [$?]"
	local s1="${s//$regex/$}"
	[ "$s1" != "$s" ] && save "$s1" "$file"
}

sync_dir() { # SRC_DIR= DST_DIR= [LINK_DIR=]
	checkvars SRC_DIR DST_DIR
	[ "$LINK_DIR" ] && {
		LINK_DIR="$(realpath "$LINK_DIR")" # --link-dest path must be absolute.
		checkvars LINK_DIR
	}

	say -n "Sync'ing dir
  src: $SRC_DIR
  dst: $PWD/$DST_DIR "
	[ "$LINK_DIR" ] && say -n "
  lnk: $LINK_DIR "
	say -n "
  ... "

	# NOTE: the dot syntax cuts out the path before it as a way to make the path relative.
	[ "$DRY" ] || must rsync --delete -aHR ${LINK_DIR:+--link-dest=$LINK_DIR} $SRC_DIR/./. $DST_DIR

	say "OK. $(dir_lean_size $dst_dir | numfmt --to=iec) bytes in destination."
}

catfile() {
	local FILE="$1"; checkvars FILE
	R1="$(cat "$FILE")"
}
