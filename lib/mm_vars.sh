# var files and dirs with include dirs.

varfile() { # DIR VAR
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

cat_varfile() { # DIR VAR [DEFAULT]
	if varfile "$1" "$2"; then
		try_catfile $R1 "$3"
		return 0
	fi
	return 1
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
cat_all_varfiles() { # [LOCAL="local "] DIR
	local DIR=$1
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
		R1+=("$LOCAL$VAR=\"${R2[$VAR]}\""$'\n')
	done
}

cat_varfiles() { # [LOCAL="local "] DIR [VAR1 ...]
	local DIR=$1; shift
	if [[ $1 ]]; then
		local LINES=()
		local VAR
		for VAR in $@; do
			if cat_varfile "$DIR" "$VAR"; then
				LINES+=("$LOCAL${VAR^^}=\"$R1\""$'\n')
			fi
		done
		R1=("${LINES[@]}")
	else
		cat_all_varfiles "$DIR"
	fi
}

# var tables -----------------------------------------------------------------

machine_vars() { # MACHINE= [VAR1 ...]
	checkvars MACHINE
	cat_varfiles var/machines/$MACHINE/vars "$@"
}

deploy_vars() { # DEPLOY= [VAR1 ...]
	machine_of_deploy "$DEPLOY"; local MACHINE=$R1
	cat_varfiles var/deploys/$DEPLOY "$@"
}

machine_var() { # MACHINE= VAR [DEFAULT]
	local VAR=$1 DEFAULT=$2
	checkvars MACHINE VAR
	cat_varfile var/machines/$MACHINE $VAR "$DEFAULT"
}

deploy_var() { # DEPLOY= VAR [DEFAULT]
	local VAR=$1 DEFAULT=$2
	checkvars DEPLOY VAR
	cat_varfile var/deploys/$DEPLOY $VAR "$DEFAULT"
}
