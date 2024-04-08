# mm lib: functions dealing with the machine & deploy database (the var dir).

# var files with include dirs ------------------------------------------------

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

# machines database ----------------------------------------------------------

check_deploy() { # DEPLOY
	checknosp "$1" "DEPLOY required"
	[ -d var/deploys/$1 ] || die "deployment unknown: $1"
}

machine_of_deploy() { # DEPLOY
	check_deploy "$1"
	R1=$(basename $(readlink var/deploys/$1/machine))
	[ "$R1" ] || die "No machine set for deploy: $1."
}

machine_of() { # MACHINE|DEPLOY
	checknosp "$1" "MACHINE or DEPLOY required"
	if [ -d var/deploys/$1 ]; then
		machine_of_deploy $1
	elif [ -d var/machines/$1 ]; then
		R1=$1
	else
		die "No MACHINE or DEPLOY named: '$1'"
	fi
}

ip_of() { # MD
	machine_of "$1"; R2=$R1
	checkfile var/machines/$R2/public_ip
	R1=$(cat $R1)
}

active_machines() {
	R1=
	local MACHINE
	for MACHINE in `ls -1 var/machines`; do
		[ "$INACTIVE" != "" -o -f "var/machines/$MACHINE/active" ] && R1+=" $MACHINE"
	done
}

each_machine() { # [MACHINES] COMMAND ...
	local MDS="$1"; shift
	local MACHINES
	if [ "$MDS" ]; then
		local MD
		for MD in $MDS; do
			ip_of $MD
			MACHINES+=" $R2"
		done
		[[ ! $QUIET && $MDS != *" "* ]] && QUIET=1
	else
		active_machines
		MACHINES="$R1"
	fi
	local CMD="$1"; shift
	for MACHINE in $MACHINES; do
		[ "$QUIET" ] || say "On machine $MACHINE:"; indent
		"$CMD" "$MACHINE" "$@"
		outdent
	done
}

# deployments database -------------------------------------------------------

deploy_vars() {
	machine_of_deploy "$1"; local MACHINE=$R1
	cat_all_varfiles var/deploys/$1
	R1+=("MACHINE=$MACHINE"$'\n')
}

active_deploys() {
	R1=
	local DEPLOY
	for DEPLOY in `ls -1 var/deploys`; do
		[ "$INACTIVE" != "" -o -f "var/deploys/$DEPLOY/active" ] && R1+=" $DEPLOY"
	done
}

each_deploy() { # [DEPLOYS] COMMAND ...
	local DEPLOYS="$1"; shift
	if [ "$DEPLOYS" ]; then
		local DEPLOY
		for DEPLOY in $DEPLOYS; do
			check_deploy $DEPLOY
		done
	else
		active_deploys
		DEPLOYS="$R1"
	fi
	local CMD="$1"; shift
	for DEPLOY in $DEPLOYS; do
		[ "$QUIET" ] || say "On deploy $DEPLOY:"; indent
		"$CMD" "$DEPLOY" "$@"
		outdent
	done
}
