# filesystem lib: ops are simplified, logged, safer, and crash on error.

pushd() { command pushd "$@" > /dev/null; }
popd()  { command popd  "$@" > /dev/null; }

check_abs_filepath() {
	[[ "${1:0:1}" == "/" ]] || die "path not absolute: $1"
	[[ "${1: -1}" == "/" ]] && die "path ends in slash: $1"
}

rel_path() { # PATH BASE_PATH
	R1=$1; [[ $1 != /* ]] && R1=$2/$1
}

checkfile() {
	[[ -f $1 ]] || die "File not found: $1"
	R1=$1
}

checkdir() {
	[[ -d $1 ]] || die "Dir not found: $1"
	R1=$1
}

# NOTE: trims content!
catfile() { # FILE [DEFAULT]
	local FILE=$1 DEFAULT=$2; checkvars FILE
	# NOTE: this is faster than "$(cat $FILE)".
	# it fails if the file contains \0 but we can't store \0
	# in bash vars anyway so just don't read binary files with this!
	[[ -f $FILE ]] || { R1=$DEFAULT; trim R1; return 1; }
	IFS= read -r -d '' R1 < "$FILE" # read exits with 1 because it hits EOF
	trim R1
}

rm_dir() { # DIR
	local dir=$1
	checkvars dir
	check_abs_filepath "$dir"
	sayn "Removing dir: $dir ... "
	[ "$DRY" ] || must dry rm -rf "$dir"
	say OK
}

rm_file() { # FILE
	local file=$1
	checkvars file
	check_abs_filepath "$file"
	sayn "Removing file: $file ... "
	if [[ ! -f $file ]]; then
		say "not found"
	else
		[ "$DRY" ] || must dry rm -f "$file"
		say OK
	fi
}

ln_file() {
	local target=$1 linkfile=$2
	checkvars target linkfile
	must dry ln -sfTv $target $linkfile
}

_mv() { # TYPE OPT OLD NEW
	local type=$1 opt=$2 old=$3 new=$4
	checkvars type old
	local s="Renaming '$old' -> '$new' ... "
	if [[ ! -e $old ]]; then
		say "$s not found: '$old'"
	elif [[ $type == dir && ! -d $old ]]; then
		say "$s not a dir: '$OLD'"
	elif [[ $type == file && ! -f $old ]]; then
		say "$s not a file: '$old'"
	elif [[ $type == file ]] && cmp -s $old $new; then
		say "$s files are the same."
		must dry rm $old
	else
		must dry mv -Tv $opt $old $new
	fi
}
mv_dir()  { _mv dir  "" "$1" "$2"; }
mv_file() { _mv file "" "$1" "$2"; }
mv_file_with_backup() { _mv file "--backup=numbered" "$1" "$2"; }
mv_dir_with_backup()  { _mv dir  "--backup=numbered" "$1" "$2"; }

# modified cp that treats DST based on whether it ends with a / or not,
# and it also does the same thing regardless of what the situation is at the destination.
_cp() { # WHAT SRC DST [USER] [MOD]
	local what=$1 src=$2 dst=$3 user=$4 mod=$5
	checkvars what src dst
	[[ $src != */ ]] || die "NYI: $src ends with slash."
	if [[ $dst == */ ]]; then # adjust $dst for chown and chmod
		dst=$dst`basename $src`
	fi
	sayn "Copying $what: '$src' -> '$dst' ... "
	[[ -e $src ]] || die: "Missing: $src"
	[[ $what == dir  ]] && { [[ -d $src ]] || die "src is not a dir."; }
	[[ $what == file ]] && { [[ -f $src ]] || die "src is not a file."; }
	must dry mkdir -p `dirname $dst` # because cp doesn't do it for us
	must dry rm -rf $dst # prevent copying _inside_ $dst if $dst is a dir
	must dry cp -rn $src $dst
	if [[ $user ]]; then
		checkvars user
		must dry chown -Rh $user:$user $dst
		[[ $mod ]] && must dry chmod -R "$mod" $dst
	fi
	say "OK"
}
cp_file() { _cp file "$@"; }
cp_dir()  { _cp dir  "$@"; }

dir_sha() { # DIR
	local DIR="$1"
	checkvars DIR
	[ -d $DIR ] || die "Dir not found: $DIR"
	local sha=$(must cd $DIR; find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha1sum | sha1sum | cut -d' ' -f1); local ret=$?
	[ $ret != 0 ] && die "sha_dir: [$ret]"
	echo "$sha"
}

# print dir size in bytes excluding files that have more than one hard-link.
dir_lean_size() { # DIR
	local DIR="$1"
	checkvars DIR
	R1=`find $DIR -type f -links 1 -printf "%s\n" | awk '{s=s+$1} END {printf "%d\n", s}'` \
		|| die "dir_lean_size: [$?]"
	[[ $R1 ]] || R1=0
}

append() { # S FILE
	local s=$1 file=$2
	checkvars s- file
	sayn "Appending ${#s} bytes to file $file ... "
	debugn "MUST: append \"$s\" $file "
	if [[ $DRY ]] || printf "%s" "$s" >> "$file"; then
		debug "[$?]"
	else
		die "append $file [$?]"
	fi
	say OK
}

remove_line() { # REGEX FILE
	local regex=$1 file=$2
	checkvars regex- file
	sayn "Removing lines containing pattern '$regex' from '$file' ... "
	if grep -q "$regex" $file; then
		[[ ! $DRY ]] && grep -v "$regex" $file > $file.temp # exits with 1
		must dry mv $file.temp $file
		say "OK"
	else
		say "none found."
	fi
}

save() { # S FILE [USER] [MODE]
	local s=$1 file=$2 user=$3 mode=$4
	checkvars s- file
	sayn "Saving ${#s} bytes to file $file ... "
	debugn "MUST: save \"$s\" $file "
	if [[ $DRY ]] || printf "%s" "$s" > "$file"; then
		debug "[$?]"
	else
		die "save $file [$?]"
	fi
	[[ $user ]] && {
		checkvars user
		must dry chown -h $user:$user $file
	}
	[[ $mode ]] && {
		checkvars mode
		must dry chmod $mode $file
	}
	say OK
}

replace_lines() { # REGEX S FILE
	local regex=$1 s=$2 file=$3
	checkvars regex- s- file
	say "Replacing line containing $regex to $s in file $file ... "
	local s="$(cat "$file")" || die "cat $file [$?]"
	local s1="${s//$regex/$}"
	[[ $s1 != $s ]] && save "$s1" "$file"
}

sync_dir() { # SRC_DIR= DST_DIR= [LINK_DIR=]
	checkvars SRC_DIR DST_DIR
	[ "$LINK_DIR" ] && {
		LINK_DIR="$(realpath "$LINK_DIR")" # --link-dest path must be absolute.
		checkvars LINK_DIR
	}

	sayn "Sync'ing dir: '$SRC_DIR' -> '$PWD/$DST_DIR'${LINK_DIR:+ lnk '$LINK_DIR'} ... "

	# NOTE: the dot syntax cuts out the path before it as a way to make the path relative.
	[ "$DRY" ] || must rsync --delete -aHR ${LINK_DIR:+--link-dest=$LINK_DIR} $SRC_DIR/./. $DST_DIR

	dir_lean_size $DST_DIR; kbytes $R1
	say "OK. $R1 bytes in destination."
}

innermost_subpath_with_file() { # FILE DIR
	local file="$1"
	local dir="$2"
	checkvars file dir
	local dir0=$dir
	dir=`dirname $dir`
	R1=; R2=
	while [[ ! -e $dir/$file ]]; do
		[[ $dir == '.' || $dir == '/' ]] && return 1
		dir=`dirname $dir`
	done
	R1=$dir
	R2=${dir0#$dir/}
}
