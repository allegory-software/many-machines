# debian package installers

# apt wrappers ---------------------------------------------------------------

install_apt() {
	save "APT::Quiet "2";" /etc/apt/apt.conf.d/10quiet
	apt_get_update
}

apt_get() { # ...
	export DEBIAN_FRONTEND=noninteractive
	must apt-get -y -qq -o=Dpkg::Use-Pty=0 $@
}

apt_get_update() {
	say; say "Updating apt package list ..."
	apt_get update --allow-releaseinfo-change
}

apt_get_install() { # ...
	say; say "Installing apt packages: $@ ..."
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

# packages -------------------------------------------------------------------

package_install() { # PACKAGE
	apt_get_install "$1"
}

package_uninstall() { # PACKAGE
	apt_get_purge "$1"
}

package_version() { # PACKAGE
	local PACKAGE=$1
	checkvars PACKAGE
	grep -A 10 "^Package: $PACKAGE\$" /var/lib/dpkg/status | grep "^Version:" | cut -d' ' -f2
}

# services -------------------------------------------------------------------

service_is_installed() {
	local SERVICE=$1; checkvars SERVICE
	systemctl status $SERVICE &> /dev/null
	[[ $? != 4 ]]
}

service_is_running() {
	local SERVICE=$1; checkvars SERVICE
	systemctl -q is-active $SERVICE
}

service_start() {
	local SERVICE=$1; checkvars SERVICE
	say "Starting $SERVICE..."
	must service $SERVICE start
}

service_stop() {
	local SERVICE=$1; checkvars SERVICE
	say "Stopping $SERVICE..."
	must service $SERVICE stop
}

# installers -----------------------------------------------------------------

install_libssl1() {
	say; sayn "Installing OpenSSL 1.1 ... "
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
	rm $pkg
}

install_mysql() {

	checkvars MYSQL_ROOT_PASS

	say; say "Installing MySQL (Percona latest)..."
	service_is_installed mysql && service_stop mysql

	apt_get_install gnupg2 lsb-release

	must wget -nv https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb -O percona.deb
	dpkg_i percona.deb
	apt_get install --fix-broken

	must rm percona.deb
	must percona-release setup -y pxc80
	apt_get_install percona-xtradb-cluster percona-xtrabackup-80 qpress

	mysql_config default "

# amazing that this is not the default...
bind-address = 127.0.0.1
mysqlx-bind-address = 127.0.0.1

# our binlog is row-based, but we still get an error when creating procs.
log_bin_trust_function_creators = 1

"

	service_start mysql

	mysql_update_pass localhost root $MYSQL_ROOT_PASS
	mysql_gen_my_cnf  localhost root $MYSQL_ROOT_PASS

	say "MySQL install done."

}

install_tarantool() { # tarantool 3.0
	say; say "Installing Tarantool..."
	must curl -L https://tarantool.io/oBlHHAA/release/3/installer.sh | bash
	apt_get_install tarantool
	# remove the source repo or it breaks apt-get. this means no updates, just fresh installs every time.
	rm_dir /etc/apt/sources.list.d/tarantool_3.list
	say "Tarantool install done."
}
