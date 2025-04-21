#
# machine-level and deploy-level modules with pre & post install hooks.
#
# Rationale: split machine & deploy installation into modules, so we can:
# - have faster dev/run cycle: install single module manually.
# - split installer into a part that runs on the target machine and a part
#   that runs on the mm machine so we can rsync files as part of installation.
# - install only what's needed, and have a library of installers ready.
# - split code into package-specific and distro-specific libraries so we
#   can support multiple distros in the future if needed.
#
# The module logic is reused for machine-level and deploy-level services
# too, which is why we use $NAMES instead of $MODULES when we're abstracting.
#

md_modules() {
	must md_var ${DEPLOY:+DEPLOY_}MODULES$1
}
md_modules_uninstall() {
	md_modules _UNINSTALL
}
md_services() {
	must md_var ${DEPLOY:+DEPLOY_}SERVICES
}

md_fn() { # ACTION= [DEPLOY=] NAME
	local name=$1
	checkvars name ACTION
	R1=
	local fn=${DEPLOY:+deploy_}${ACTION}_${name}
	if ! declare -F $fn > /dev/null; then
		fn=default_${DEPLOY:+deploy_}${ACTION}
		if ! declare -F $fn > /dev/null; then
			return 1
		fi
	fi
	R1=$fn
}

md_version() {
	ACTION=version md_fn "$1" && $fn
}
default_version() {
	package_version $1
}

_md_with_action_fn() { # ACTION= [DEPLOY=] NAME1 ...
	R1=
	local name
	for name in "$@"; do
		md_fn $name && R1+="$name "
	done
	return 0
}

_each() { # ACTION= [DRY=1] [DEPLOY=] NAME1 ...
	local name
	for name in "$@"; do
		md_fn $name && dry $R1 $name
	done
	return 0
}

_md_list() { # LIST=
	$LIST; local names=($R1)
	if [[ $DEPLOY ]]; then
		printf "$WHITE%-10s %-10s$ENDCOLOR %s\n" $MACHINE $DEPLOY "${names[*]}"
	else
		printf "$WHITE%-10s$ENDCOLOR %s\n" $MACHINE "${names[*]}"
	fi
}
_md_names() { # [REVERSE=1] LIST= [all | NAME1 ...]
	local names=$*
	[[ $names ]] || { _md_list; return 2; }
	if [[ $names == all ]]; then
		$LIST; names=$R1
		[[ $REVERSE ]] && names=`awk '{for(i=NF;i>0;i--) printf("%s ",$i)}' <<<"$names"`
	fi
	checkvars names-
	R1=$names
}
_md_action() { # ACTION= [REMOTE=] [VARS=] LIST= [REVERSE=1] [all | NAME1 ...]
	checkvars ACTION
	_md_names "$@"; [[ $? == 2 ]] && return
	local names=$R1
	if [[ $REMOTE ]]; then
		VARS="ACTION $VARS" md_ssh_script _each $names
	else
		_each $names
	fi
}

# executed both locally (pre/post functions) and remotely (main function).
_md_combined_action() { # ACTION= [MODULE1 ...]
	_md_names "$@"; [[ $? == 2 ]] && return
	local names=$R1
	local module
	for module in $names; do
		ACTION=pre$ACTION  _md_action $module
		REMOTE=1           _md_action $module
		ACTION=post$ACTION _md_action $module
	done
}
md_install()   { ACTION=install   LIST=md_modules           _md_combined_action "$@"; }
md_uninstall() { ACTION=uninstall LIST=md_modules REVERSE=1 _md_combined_action "$@"; }
_md_rename()   { ACTION=rename    LIST=md_modules           _md_combined_action "$@"; }

default_install()   { package_install   "$1"; }
default_uninstall() { package_uninstall "$1"; }

# executed remotely.
md_start() { ACTION=start REMOTE=1 LIST=md_services _md_action "$@"; }
md_stop()  { ACTION=stop  REMOTE=1 LIST=md_services _md_action "$@"; }

default_start() { service_start "$@"; }
default_stop()  { service_stop  "$@"; }

# executed locally on the target machine.
_deploy_services() { R1=$DEPLOY_SERVICES; }
deploy_start()  { ACTION=start LIST=_deploy_services _md_action "$@"; }
deploy_stop()   { ACTION=stop  LIST=_deploy_services _md_action "$@"; }

# executed locally on the mm machine.
_md_backup_modules() { md_modules; _md_with_action_fn $R1; }
_md_backup()  { ACTION=backup  LIST=_md_backup_modules _md_action "$@"; }
_md_restore() { ACTION=restore LIST=_md_backup_modules _md_action "$@"; }

# executed locally on the target machine.
md_is_running() { # SERVICE
	local SERVICE=$1
	checkvars SERVICE
	ACTION=is_running md_fn $SERVICE || die "$SERVICE does not have an is_running function."
	$R1 $SERVICE
}
default_is_running() { service_is_running "$1"; }

md_status() { # [DOWN=1] ["SERVICE1 ..."]
	local svar=1; [[ $1 ]] || svar=${DEPLOY:+DEPLOY_}SERVICES
	local services=${!svar}
	for SERVICE in $services; do
		local VERSION=`md_version $SERVICE`
		local STATUS
		if md_is_running $SERVICE; then
			[[ $DOWN ]] && continue
			STATUS=${LIGHTGRAY}up${ENDCOLOR}
			SERVICE=${LIGHTGRAY}${LIGHTGRAY}${SERVICE}${ENDCOLOR}
		else
			STATUS=${LIGHTRED}DOWN!${ENDCOLOR}
			SERVICE=${BG_RED}${WHITE}${SERVICE}${ENDCOLOR}
		fi
		printf "%s\n" $MACHINE ${DEPLOY:-*} $SERVICE "${STATUS:--}" "${VERSION:--}"
	done
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

md_rename() { # MACHINE|DEPLOY NEW_NAME ...
	machine_of "$1"; shift
	if [[ $DEPLOY ]]; then
		deploy_rename "$@"
	else
		machine_rename "$@"
	fi
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
