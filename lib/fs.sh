# filesystem lib: ops are simplified, logged, safer, and crash on error.

pushd() { command pushd "$@" > /dev/null; }
popd()  { command popd  "$@" > /dev/null; }

check_abs_filepath() {
	[ "${1:0:1}" == "/" ] || die "path not absolute: $1"
	[ "${1: -1}" == "/" ] && die "path ends in slash: $1"
}

checkfile() {
    [ -f "$1" ] || die "File not found: $1"
    R1="$1"
}

# NOTE: trims content!
catfile() { # FILE
	local FILE="$1"; checkvars FILE
	# NOTE: this is faster than "$(cat $FILE)".
	# it fails if the file contains \0 but we can't store \0
	# in bash vars anyway so just don't read binary files with this!
	[ -f "$FILE" ] || die "catfile $FILE [$?]"
	IFS= read -r -d '' R1 < "$FILE" # read exits with 1 because it hits EOF
	trim R1
}

# NOTE: trims content!
try_catfile() { # FILE [DEFAULT]
	local FILE="$1"; checkvars FILE
	if [ ! -f "$FILE" ]; then
		R1="$2"; trim R1
	else
		catfile "$FILE"
	fi
}

rm_dir() { # DIR
	local dir="$1"
	checkvars dir
	check_abs_filepath "$dir"
	say -n "Removing dir: $dir ... "
	[ "$DRY" ] || must rm -rf "$dir"
	say OK
}

rm_file() { # FILE
	local file="$1"
	checkvars file
	check_abs_filepath "$file"
	say -n "Removing file: $file ... "
	[ "$DRY" ] || must rm -f "$file"
	say OK
}

# modified cp that treats DST based on whether it ends with a / or not.
_cp() { # WHAT SRC DST [USER] [MOD]
	local what="$1"
	local src="$2"
	local dst="$3"
	local user="$4"
	local mod="$5"
	checkvars what src dst
	[[ $src != */ ]] || die "NYI: $src ends with slash."
	if [[ $dst == */ ]]; then # adjust $dst for chown and chmod
		dst=$dst`basename $src`
	fi
	say -n "Copying $what:
$INDENT  src: $src
$INDENT  dst: $dst ... "
	[[ -e $src ]] || die: "Missing: $src"
	[[ $what == dir  ]] && { [[ -d $src ]] || die "src is not a dir."; }
	[[ $what == file ]] && { [[ -f $src ]] || die "src is not a file."; }
	dry must mkdir -p `dirname $dst` # because cp doesn't do it for us
	dry must rm -rf $dst # prevent copying _inside_ $dst if $dst is a dir
	dry must cp -r $src $dst
	if [[ $user ]]; then
		checkvars user
		dry must chown -R $user:$user $dst
		[[ $mod ]] && dry must chmod -R "$mod" $dst
	fi
	say "OK"
}
cp_file() { _cp file "$@"; }
cp_dir()  { _cp dir  "$@"; }

sha_dir() { # DIR
	local DIR="$1"
	checkvars DIR
	[ -d $DIR ] || die "Dir not found: $DIR"
	local sha=$(find $DIR -type f -print0 | LC_ALL=C sort -z | xargs -0 sha1sum | sha1sum | cut -d' ' -f1); local ret=$?
	[ $ret != 0 ] && die "sha_dir: [$ret]"
	echo "$sha"
}

# print dir size in bytes excluding files that have more than one hard-link.
dir_lean_size() { # DIR
	local DIR="$1"
	checkvars DIR
	local s="$(find $DIR -type f -links 1 -printf "%s\n" | awk '{s=s+$1} END {print s}')"; local ret=$?
	[ $ret != 0 ] && die "dir_lean_size: [$ret]"
	[ "$s" ] || s=0
	echo "$s"
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

remove_line() { # REGEX FILE
	local regex="$1"
	local file="$2"
	checkvars regex- file
	say -n "Removing lines containing pattern /$regex/ from $file... "
	if grep -q "$regex" $file; then
		grep -v "$regex" $file > $file.temp # exits with 1
		must mv $file.temp $file
		say "OK"
	else
		say "none found."
	fi
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

	say -n "Sync'ing dir:
$INDENT  src: $SRC_DIR
$INDENT  dst: $PWD/$DST_DIR "
	[ "$LINK_DIR" ] && say -n "
$INDENT  lnk: $LINK_DIR "
	say -n " ... "

	# NOTE: the dot syntax cuts out the path before it as a way to make the path relative.
	[ "$DRY" ] || must rsync --delete -aHR ${LINK_DIR:+--link-dest=$LINK_DIR} $SRC_DIR/./. $DST_DIR

	say "OK. $(dir_lean_size $dst_dir | numfmt --to=iec) bytes in destination."
}
