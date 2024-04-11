# var files with include dirs

varfile() { # DIR VAR_NAME
	local DIR="$1"
	local FILE="${2,,}"
	R1=
	[ -f $DIR/$FILE ] && { R1=$DIR/$FILE; return 0; }
	local INC; for INC in `find -L $DIR -maxdepth 10 -name '.?*'`; do
		[ -d $INC ] || continue
		[ -f $INC/$FILE ] && { R1=$INC/$FILE; return 0; }
	done
	return 1
}

cat_varfile() { # DIR VAR_NAME [DEFAULT_VALUE]
	if varfile "$1" "$2"; then
		try_catfile $R1 "$3"
		return 0
	fi
	return 1
}

cat_varfiles() { # DIR VAR_NAME1 ...
	local DIR="$1"; shift
	local LINES=()
	local VAR
	for VAR in $@; do
		if cat_varfile "$DIR" "$VAR"; then
			LINES+=("${VAR^^}=\"$R1\""$'\n')
		fi
	done
	R1=("${LINES[@]}")
}

_add_varfiles() { # DIR
	local FILE
	for FILE in `ls -1Lp $1 | grep -v /`; do # list files & file symlinks only (and no dotfiles)
		local VAR="${FILE^^}"
		if [[ ! -v R2[$VAR] ]]; then
			catfile $1/$FILE
			R2[$VAR]="$R1"
		fi
	done
}
cat_all_varfiles() { # DIR
	local DIR="$1"
	checkvars DIR
	declare -A R2
	_add_varfiles $DIR
	local INC; for INC in `find -L $DIR -maxdepth 10 -name '.?*'`; do
		[ -d $INC ] || continue
		_add_varfiles $INC
	done
	R1=()
	local VAR
	for VAR in "${!R2[@]}"; do
		R1+=("$VAR=\"${R2[$VAR]}\""$'\n')
	done
}

