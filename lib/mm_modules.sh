# machine-level and deploy-level modules with pre & post install hooks.
#
# rationale: split machine & deploy installation into modules, so we can:
# - have faster dev/run cycle: install single module manually.
# - split installer into a part that runs on the target machine and a part
#   that runs on the mm machine so we can rsync files as part of installation.
# - install only what's needed, and have a library of installers ready.
# - split code into package-specific and distro-specific libraries.

md_modules() {
	if [[ $MM_DEPLOY ]]; then
		must deploy_var DEPLOY_MODULES
	else
		must machine_var MODULES
	fi
}

_each_module() { # action= MODULE1 ...
	local mod
	for mod in "$@"; do
		local fn=${action}_${mod}
		if ! declare -F $fn > /dev/null; then
			fn=default_${action}
			if ! declare -F $fn > /dev/null; then
				continue
			fi
		fi
		$fn $mod
	done
}
_md_install() { # [un=un] [MODULE1 ...]
	local MODULES="$*"; [[ $MODULES == all ]] || { md_modules; MODULES=$R1; }
	local d; [[ $MM_DEPLOY ]] && d=deploy_
	local s; [[ $MM_DEPLOY ]] && s=deploy || s=machine
	action=${d}pre${un}install _each_module $MODULES
	ssh_script_$s "action=${d}${un}install _each_module" $MODULES
	action=${d}post${un}install _each_module $MODULES
}
md_install()   { un=   _md_install "$@"; }
md_uninstall() { un=un _md_install "$@"; }

md_list_modules() { # DEPLOY=|MACHINE=
	md_modules; local modules=($R1)
	if [[ $MM_DEPLOY ]]; then
		printf "%-10s %-10s %s\n" $MACHINE $DEPLOY "${modules[*]}"
	else
		printf "%-10s %s\n" $MACHINE "${modules[*]}"
	fi
}

# version reporting ----------------------------------------------------------

machine_component_version() { # ["COMPONENT1 ..."]
	local COMPS=$1; [[ $COMPS ]] || { functions_with_prefix version_; COMPS=$R1; }
	for COMP in $COMPS; do
		local VERSION=`version_$COMP 2>/dev/null`
		printf "%s\n" $MACHINE $COMP "${VERSION:--}"
	done
}

deploy_component_version() { # DEPLOY= ["COMPONENT1 ..."]
	checkvars DEPLOY
	local COMPS=$1; [[ $COMPS ]] || { functions_with_prefix deploy_version_; COMPS=$R1; }
	for COMP in $COMPS; do
		local VERSION=`deploy_version_$COMP 2>/dev/null`
		printf "%s\n" $MACHINE $DEPLOY $COMP "${VERSION:--}"
	done
}

md_component_version() {
	if [[ $MM_DEPLOY ]]; then
		deploy_component_version "$@"
	else
		machine_component_version "$@"
	fi
}
