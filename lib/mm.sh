# mm lib: functions reading var/machines and var/deploys.

mm_update() {
	git_clone_for root git@github.com:allegory-software/many-machines2 /opt/mm master mm
	# install globally
	must ln -sf /opt/mm/mma     /usr/bin/mma
	must ln -sf /opt/mm/mm      /usr/bin/mm
	must ln -sf /opt/mm/lib/all /usr/bin/mmlib
}

mc_conf_upload() {
	check_machine "$1"
	say "Uploading mc config files to machine '$1' ..."
	cp_dir ~/.config/mc etc/home/.config/
	SRC_DIR=etc/home/./.config/mc DST_DIR=/root DST_MACHINE=$1 rsync_dir
	ssh_script $1 "mc_conf_spread"
}

mc_conf_spread() {
	local USER
	for USER in `ls -1 /home`; do
		say "Copying mc config files to user '$USER' ..."
		indent
		cp_dir /root/.config/mc /home/$USER/.config/ $USER
		outdent
	done
}

# machines database ----------------------------------------------------------

check_machine() { # MACHINE
	checknosp "$1" "MACHINE required"
	[ -d var/machines/$1 ] || die "Machine unknown: $1"
}

check_deploy() { # DEPLOY
	checknosp "$1" "DEPLOY required"
	[ -d var/deploys/$1 ] || die "Deployment unknown: $1"
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
		("$CMD" "$MACHINE" "$@")
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
		[[ "$INACTIVE" != "" || -f var/deploys/$DEPLOY/active ]] && R1+=" $DEPLOY"
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
