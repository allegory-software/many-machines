# apt wrappers

package_install() { # PACKAGE
	if declare -F "install_${1}" > /dev/null; then
		install_${1}
	else
		apt_get_install $1
	fi
}

install_apt() {
	save "APT::Quiet "2";" /etc/apt/apt.conf.d/10quiet
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
