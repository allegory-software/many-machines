apt_get() { # ...
	export DEBIAN_FRONTEND=noninteractive
	must apt-get -y -qq -o=Dpkg::Use-Pty=0 $@
}

apt_get_update() {
	say "Updating package list..."
	apt_get update --allow-releaseinfo-change
}

apt_get_install() { # ...
	say "Installing packages: $@..."
	apt_get install $@
}
