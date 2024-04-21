# remote package installer with pre/post install hooks executed on the mm machine.

_package_install() { # PACKAGE1 ...
	local pkg
	for pkg in "$@"; do
		if declare -F "${prefix}install_${pkg}" > /dev/null; then
			${prefix}install_${pkg}
		elif [[ ! $prefix ]]; then
			apt_get_install $pkg
		fi
	done
}
package_install() { # PACKAGE1 ...
	prefix=pre _package_install "$@"
	ssh_script_machine "prefix= _package_install" "$@"
	prefix=post _package_install "$@"
}

# apt wrappers

install_apt() {
	save "APT::Quiet "2";" /etc/apt/apt.conf.d/10quiet
	apt_get_update
}

apt_get() { # ...
	export DEBIAN_FRONTEND=noninteractive
	must apt-get -y -qq -o=Dpkg::Use-Pty=0 $@
}

apt_get_update() {
	say "Updating package list ..."
	apt_get update --allow-releaseinfo-change
}

apt_get_install() { # ...
	say "Installing packages: $@ ..."
	apt_get install $@
}

dpkg_i() {
	export DEBIAN_FRONTEND=noninteractive
	say "Installing dpkg: $@ ..."
	must dpkg -i --force-confold "$@"
}
