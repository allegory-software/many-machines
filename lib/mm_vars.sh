# var files and dirs with include dirs.

varfile() { # DIR VAR
	local DIR="$1"
	local FILE="${2,,}" # VAR in lowercase
	R1=
	[[ -f $DIR/$FILE ]] && { R1=$DIR/$FILE; return 0; }
	[[ $THIS_MACHINE && -f $DIR/.$FILE ]] && { R1=$DIR/.$FILE; return 0; }
	local INC found
	# gor through all include dirs recursively with a single file command.
	for INC in `find -L $DIR -maxdepth 10 -type d -name '.?*' | sort`; do
		# not stopping when a file is found to allow overriding,
		# if you prefix the include dirs to force an include order.
		[[ -f $INC/$FILE ]] && { R1=$INC/$FILE; found=1; }
		[[ $THIS_MACHINE && -f $INC/.$FILE ]] && { R1=$INC/.$FILE; found=1; }
	done
	[[ $found ]]
}

cat_varfile() { # DIR VAR [DEFAULT]
	varfile "$1" "$2" || { R1=$3; return 1; }
	catfile $R1 "$3"
}

_add_varfiles() { # DIR
	# list files & file symlinks only, excluding dotfiles if not invoked
	# from the mm command, which prevents private data leaks to machines.
	ls_dir $1
	local files=("${R1[@]}")
	local FILE
	for FILE in "${files[@]}"; do
		[[ -f $1/$FILE ]] || continue # skip dirs
		local VAR=${FILE#.} # remove dot if private var
		[[ $VAR != $FILE && ! $THIS_MACHINE ]] && continue # don't leak it
		VAR=${VAR^^}
		if [[ ! -v R2[$VAR] ]]; then
			must catfile $1/$FILE
			R2[$VAR]="$R1"
		fi
	done
}
cat_all_varfiles() { # [PREFIX="local "] DIR
	local DIR=$1
	checkvars DIR
	local -A R2 # init R2 as local map (even if already exists).
	_add_varfiles $DIR
	# go through all include dirs recursively with a single find command.
	local INC; for INC in `find -L $DIR -maxdepth 10 -type d -name '.?*' | sort`; do
		_add_varfiles $INC
	done
	R1=()
	local VAR
	for VAR in "${!R2[@]}"; do
		R1+=("$PREFIX$VAR=\"${R2[$VAR]}\""$'\n')
	done
}

cat_varfiles() { # [PREFIX="local "] DIR [VAR1 ...]
	local DIR=$1; shift
	if [[ $1 ]]; then
		local LINES=()
		local VAR
		for VAR in $@; do
			if cat_varfile "$DIR" "$VAR"; then
				LINES+=("$PREFIX${VAR^^}=\"$R1\""$'\n')
			fi
		done
		R1=("${LINES[@]}")
	else
		cat_all_varfiles "$DIR"
	fi
}

# machine & deploy vars ------------------------------------------------------

md_vardir() { # MACHINE=|DEPLOY=
	if [[ $DEPLOY ]]; then
		checkvars DEPLOY
		R1=var/deploys/$DEPLOY
	else
		checkvars MACHINE
		R1=var/machines/$MACHINE
	fi
}

md_varfile() { # MACHINE=|DEPLOY= VAR
	md_vardir; varfile $R1 "$1"
}

md_vars() { # MACHINE=|DEPLOY= [VAR1 ...]
	md_vardir; cat_varfiles $R1 "$@"
}

md_var() { # MACHINE=|DEPLOY= VAR [DEFAULT]
	local VAR=$1 DEFAULT=$2
	checkvars VAR
	md_vardir; cat_varfile $R1 $VAR "$DEFAULT"
}

mm_var() { cat_varfile var $1; }

local_md_vars() {
	PREFIX="local " md_vars "$@"; R1="${R1[*]}"
}
