# modular installer with pre/post install hooks executed on the mm machine.
# can install/configure modules on a machine or on a deployment.

_on_each_module() { # action= MODULE1 ...
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
		say
	done
}
_each_module() { # script_type= action= MODULE1 ...
	checkvars action
	action=stop _on_each_module "$@"
	action=pre${action} _on_each_module "$@"
	ssh_script_${script_type} "action=$action _on_each_module" "$@"
	action=post${action} _on_each_module "$@"
}

deploy_install() { # [un=un] DEPLOY= MODULE1 ...
	checkvars DEPLOY
	say "${un^}Installing on deploy '$DEPLOY': $* ... "
	script_type=deploy action=deploy_stop _each_module "$@"
	script_type=deploy action=deploy_${un}install _each_module "$@"
	if [[ ! $un ]]; then
		script_type=deploy action=deploy_start _each_module "$@"
	fi
}
machine_install() { # [un=un] MACHINE= MODULE1 ...
	checkvars MACHINE
	say "${un^}Installing on machine '$MACHINE': $* ... "
	script_type=machine action=stop _each_module "$@"
	script_type=machine action=${un}install _each_module "$@"
	if [[ ! $un ]]; then
		script_type=machine action=start _each_module "$@"
	fi
}
md_install() { # [un=un] MACHINE=|DEPLOY= MODULE1 ...
	if [[ $MM_DEPLOY ]]; then
		deploy_install "$@"
	else
		machine_install "$@"
	fi
}

# default installers

default_install() {
	apt_get_install $1
}

default_uninstall() {
	apt_get_purge $1
}
