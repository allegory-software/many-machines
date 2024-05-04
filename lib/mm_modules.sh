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

_each() { # ACTION= NAME1 ...
	local name
	for name in "$@"; do
		local fn=${ACTION}_${name}
		if ! declare -F $fn > /dev/null; then
			fn=default_${ACTION}
			if ! declare -F $fn > /dev/null; then
				continue
			fi
		fi
		$fn $name
	done
	return 0
}
_md_action() { # ACTION= [REMOTE=] LIST= [un=] NAME1 ...
	checkvars ACTION
	local NAMES=$*
	[[ $NAMES ]] || {
		_md_list
		return 0
	}
	if [[ $NAMES == all ]]; then
		$LIST; NAMES=$R1
		[[ $un ]] && NAMES=`awk '{for(i=NF;i>0;i--) printf("%s ",$i)}' <<<"$NAMES"`
	fi
	local ACTION=$ACTION
	if [[ $DEPLOY ]]; then
		ACTION=deploy_$ACTION
	fi
	if [[ $REMOTE ]]; then
		VARS="ACTION" md_ssh_script _each $NAMES
	else
		_each $NAMES
	fi
}

# executed both locally (pre/post functions) and remotely (main function).
_md_install() { # [un=un] [MODULE1 ...]
	ACTION=pre${un}install       LIST=md_modules _md_action $@
	ACTION=${un}install REMOTE=1 LIST=md_modules _md_action $@
	ACTION=post${un}install      LIST=md_modules _md_action $@
}
md_install()   { un=   _md_install "$@"; }
md_uninstall() { un=un _md_install "$@"; }

default_install()   { package_install   "$1"; }
default_uninstall() { package_uninstall "$1"; }

# executed remotely.
md_start() { ACTION=start REMOTE=1 LIST=md_services _md_action $@; }
md_stop()  { ACTION=stop  REMOTE=1 LIST=md_services _md_action $@; }

default_start() { service_start "$@"; }
default_stop()  { service_stop  "$@"; }

md_status() { # ["SERVICE1 ..."]
	if [[ $DEPLOY ]]; then
		for SERVICE in $DEPLOY_SERVICES; do
			local VERSION=`deploy_version_$SERVICE 2>/dev/null`
			local STATUS; deploy_is_running_$SERVICE && STATUS=UP || STATUS=DOWN!
			printf "%s\n" $MACHINE $DEPLOY $SERVICE "${STATUS:--}" "${VERSION:--}"
		done
	else
		local SERVICES=${1:-$SERVICES}
		for SERVICE in $SERVICES; do
			local VERSION=`version_$SERVICE 2>/dev/null`
			local STATUS; service_is_running "$SERVICE" && STATUS=UP || STATUS=DOWN!
			printf "%s\n" $MACHINE '*' $SERVICE "${STATUS:--}" "${VERSION:--}"
		done
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
