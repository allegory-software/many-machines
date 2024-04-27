# debian package installers

# packages -------------------------------------------------------------------

install_apt() {
	save "APT::Quiet "2";" /etc/apt/apt.conf.d/10quiet
	apt_get_update
}

apt_get() { # ...
	export DEBIAN_FRONTEND=noninteractive
	must apt-get -y -qq -o=Dpkg::Use-Pty=0 $@
}

apt_get_update() {
	say "Updating apt package list ..."
	apt_get update --allow-releaseinfo-change
}

apt_get_install() { # ...
	say "Installing apt packages: $@ ..."
	apt_get install $@
}

apt_get_purge() {
	say "Purging apt packages: $@ ..."
	apt_get purge $@
}

dpkg_i() {
	export DEBIAN_FRONTEND=noninteractive
	say "Installing dpkg: $@ ..."
	must dpkg -i --force-confold "$@"
}

apt_has_install() { # PACKAGE
	apt-cache show "$1" &> /dev/null
}

package_version() { # PACKAGE
	local PACKAGE=$1
	checkvars PACKAGE
	grep -A 10 "^Package: $PACKAGE\$" /var/lib/dpkg/status | grep "^Version:" | cut -d' ' -f2
}

# services -------------------------------------------------------------------

service_is_installed() {
	local SERVICE=$1; checkvars SERVICE
	systemctl status "$SERVICE" &> /dev/null
}

is_running() {
	systemctl -q is-active "$1"
}

service_start() {
	local SERVICE=$1; checkvars SERVICE
	say "Starting $SERVICE..."
	must service "$SERVICE" start
}

service_stop() {
	local SERVICE=$1; checkvars SERVICE
	say "Stopping $SERVICE..."
	must service "$SERVICE" stop
}

service_status() { # ["SERVICE1 ..."]
	[[ $1 ]] && SERVICES=$1
	for SERVICE in $SERVICES; do
		local VERSION
		VERSION=`version_$SERVICE 2>/dev/null`
		is_running "$SERVICE" && STATUS=UP || STATUS=DOWN!
		printf "%s\n" $MACHINE $SERVICE "${STATUS:--}" "${VERSION:--}"
	done
}

# package modules ------------------------------------------------------------

default_install() {
	apt_get_install "$1"
}

default_uninstall() {
	apt_get_purge "$1"
}

# custom packages ------------------------------------------------------------

version_cron() {
	# this is too slow...
	#apt show cron 2>/dev/null | grep Version: | cut -d' ' -f2
	package_version cron
}

install_low_ports() {
	say; say "Configuring kernel to allow binding to ports < 1024 by any user..."
	save 'net.ipv4.ip_unprivileged_port_start=0' \
		/etc/sysctl.d/50-unprivileged-ports.conf
	must sysctl --system >/dev/null
}

install_nginx() {
	apt_get_install nginx
	say "Configuring nginx..."
	# add dhparam.pem from mm (dhparam is public).
	save "$DHPARAM" /etc/nginx/dhparam.pem
	# remove nginx placeholder vhost.
	must rm -f /etc/nginx/sites-enabled/default
	is_running nginx && nginx -s reload
}

install_libssl1() {
	say; say -n "Installing OpenSSL 1.1 ... "
	dpkg-query -l libssl1.1 2>/dev/null >/dev/null && { say "already installed."; return 0; }
	os_version
	[[ $R1 == ubuntu && $R2 == 22.* ]] || { 
		say "NYI for OS: $R1 $R2."
		return 0
	}
	say
	local pkg=libssl1.1_1.1.1f-1ubuntu2.22_amd64.deb
	must wget -q http://nz2.archive.ubuntu.com/ubuntu/pool/main/o/openssl/$pkg
	dpkg_i $pkg
}
