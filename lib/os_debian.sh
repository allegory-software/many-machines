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
	must systemctl start $SERVICE
}

service_stop() {
	local SERVICE=$1; checkvars SERVICE
	say "Stopping $SERVICE..."
	must systemctl stop $SERVICE
}

service_disable() {
	local SERVICE=$1; checkvars SERVICE
	service_is_running $SERVICE && \
		service_stop $SERVICE
	if service_is_installed $SERVICE; then
		say; say "Disabling $SERVICE ..."
		must systemctl disable $SERVICE
	else
		say; say "Disabling $SERVICE ... not installed."
	fi
}

service_enable() {
	local SERVICE=$1; checkvars SERVICE
	say; say "Enabling $SERVICE..."
	must systemctl enable $SERVICE
}

# installers -----------------------------------------------------------------

install_vbox() {
    apt install -y build-essential dkms linux-headers-$(uname -r)
    mount -o remount,ro,exec /media/cdrom
    /media/cdrom/VBoxLinuxAdditions.run
}

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
	curl -L https://tarantool.io/release/3/installer.sh | bash
	apt_get_install tarantool
	apt_get_install tt
	say "Tarantool install done."
}

install_rpcbind() {
	service_enable rpcbind
	service_enable rpcbind.socket
}
uninstall_rpcbind() {
	service_disable rpcbind.socket
	service_disable rpcbind
}

install_avahi_daemon() {
	service_enable avahi-daemon
	service_enable avahi-daemon.socket
}
uninstall_avahi_daemon() {
	service_disable avahi-daemon.socket
	service_disable avahi-daemon
}

install_iptables() {
	service_enable netfilter-persistent
	service_start netfilter-persistent
}
uninstall_iptables() {
	service_disable netfilter-persistent
	iptables -F
}

install_nftables() {
	save "
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
	chain input {
		type filter hook input priority 0; policy drop;

		iif lo accept

		ct state established,related accept

		ip protocol icmp accept
		#ip6 icmpv6 accept

		tcp dport { ${TCP_PORTS//[[:space:]]/,} } accept
		udp dport { ${UDP_PORTS//[[:space:]]/,} } accept
	}
}
" /etc/nftables.conf
	nft -f /etc/nftables.conf
	service_enable nftables
}
uninstall_nftables() {
	systemctl disable nftables
	nft flush ruleset
}
