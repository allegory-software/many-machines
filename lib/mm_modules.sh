# machine-level and deploy-level modules with pre & post install hooks.
#
# rationale: split machine & deploy installation into modules, so we can:
# - have faster dev/run cycle: install single module manually.
# - split installer into a part that runs on the target machine and a part
#   that runs on the mm machine so we can rsync files as part of installation.
# - install only what's needed, and have a library of installers ready.
# - split code into package-specific and distro-specific libraries.

md_modules() {
	must md_var ${DEPLOY:+DEPLOY_}MODULES
}
md_services() {
	must md_var ${DEPLOY:+DEPLOY_}SERVICES
}
_md_list() { # LIST= DEPLOY=|MACHINE=
	$LIST; local names=($R1)
	if [[ $DEPLOY ]]; then
		printf "%-10s %-10s %s\n" $MACHINE $DEPLOY "${names[*]}"
	else
		printf "%-10s %s\n" $MACHINE "${names[*]}"
	fi
}

_each() { # ACTION= [DRY=1] NAME1 ...
	local name
	for name in "$@"; do
		local fn=${ACTION}_${name}
		if ! declare -F $fn > /dev/null; then
			fn=default_${ACTION}
			if ! declare -F $fn > /dev/null; then
				continue
			fi
		fi
		dry $fn $name
	done
	return 0
}
_md_action() { # ACTION= [REMOTE=] [VARS=] LIST= [REVERSE=1] all | NAME1 ...
	checkvars ACTION
	local NAMES=$*
	[[ $NAMES ]] || {
		_md_list
		return 0
	}
	if [[ $NAMES == all ]]; then
		$LIST; NAMES=$R1
		[[ $REVERSE ]] && NAMES=`awk '{for(i=NF;i>0;i--) printf("%s ",$i)}' <<<"$NAMES"`
	fi
	local ACTION=$ACTION
	if [[ $DEPLOY ]]; then
		ACTION=deploy_$ACTION
	fi
	if [[ $REMOTE ]]; then
		VARS="ACTION DRY $VARS" md_ssh_script _each $NAMES
	else
		_each $NAMES
	fi
}

# executed both locally (pre/post functions) and remotely (main function).
_md_combined_action() { # ACTION= [MODULE1 ...]
	ACTION=pre$ACTION  _md_action "$@"
	REMOTE=1           _md_action "$@"
	ACTION=post$ACTION _md_action "$@"
}
md_install()   { ACTION=install   LIST=md_modules           _md_combined_action "$@"; }
md_uninstall() { ACTION=uninstall LIST=md_modules REVERSE=1 _md_combined_action "$@"; }
_md_rename()   { ACTION=rename    LIST=md_modules           _md_combined_action "$@"; }

default_install()   { package_install   "$1"; }
default_uninstall() { package_uninstall "$1"; }

# executed remotely.
md_start() { ACTION=start REMOTE=1 LIST=md_services _md_action $@; }
md_stop()  { ACTION=stop  REMOTE=1 LIST=md_services _md_action $@; }

default_start() { service_start "$@"; }
default_stop()  { service_stop  "$@"; }

# executed locally
_deploy_services() { R1=$DEPLOY_SERVICES; }
deploy_start()  { ACTION=start LIST=_deploy_services _md_action $@; }
deploy_stop()   { ACTION=stop  LIST=_deploy_services _md_action $@; }

md_status() { # [DOWN=1] ["SERVICE1 ..."]
	if [[ $DEPLOY ]]; then
		for SERVICE in $DEPLOY_SERVICES; do
			local VERSION=`deploy_version_$SERVICE 2>/dev/null`
			local STATUS; deploy_is_running_$SERVICE && STATUS=UP || STATUS=DOWN!
			[[ $DOWN && $STATUS == UP ]] && continue
			printf "%s\n" $MACHINE $DEPLOY $SERVICE "${STATUS:--}" "${VERSION:--}"
		done
	else
		local SERVICES=${1:-$SERVICES}
		for SERVICE in $SERVICES; do
			local VERSION=`version_$SERVICE 2>/dev/null`
			local STATUS; service_is_running "$SERVICE" && STATUS=UP || STATUS=DOWN!
			[[ $DOWN && $STATUS == UP ]] && continue
			printf "%s\n" $MACHINE '*' $SERVICE "${STATUS:--}" "${VERSION:--}"
		done
	fi
}

check_md_new_name() {
	local NAME=$1
	checkvars NAME
	[[ ! -d var/deploys/$NAME  ]] || die "A deploy with this name already exists: '$NAME'."
	[[ ! -d var/machines/$NAME ]] || die "A machine with this name already exists: '$NAME'."
}

deploy_rename() { # DEPLOY= NEW_NAME ...
	local DEPLOY1=$1
	check_deploy $DEPLOY
	check_md_new_name $DEPLOY1

	md_ssh_script "deploy_stop all"

	VARS="DEPLOY1" _md_rename all

	must dry mv \
		var/deploys/$DEPLOY \
		var/deploys/$DEPLOY1

	DEPLOY=$DEPLOY1 md_ssh_script "deploy_start all"
}

machine_rename() { # MACHINE= NEW_NAME ...
	local MACHINE1=$1
	check_machine $MACHINE
	check_md_new_name $MACHINE1

	VARS="MACHINE1" _md_rename all

	must dry mv \
		var/machines/$MACHINE \
		var/machines/$MACHINE1

	INACTIVE=1 active_deploys; local deploys=$R1
	local deploy
	for deploy in $R1; do
		if try_machine_of_deploy $deploy && [[ $R1 == $MACHINE ]]; then
			ln_file ../../machines/$MACHINE1 var/deploys/$deploy/machine
		fi
	done
}

# version reporting ----------------------------------------------------------

md_component_version() { # DEPLOY= [COMPONENT1 ...]
	local d=${DEPLOY:+deploy_}
	local COMPS=$*; [[ $COMPS ]] || { functions_with_prefix ${d}version_; COMPS=$R1; }
	for COMP in $COMPS; do
		local VERSION=`${d}version_$COMP 2>/dev/null`
		printf "%s\n" $MACHINE ${DEPLOY:-*} $COMP "${VERSION:--}"
	done
}
