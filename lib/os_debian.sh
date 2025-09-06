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

package_install() { # PACKAGE1 ...
	apt_get_install "$@"
}

package_uninstall() { # PACKAGE1 ...
	apt_get_purge "$@"
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

service_restart() {
	local SERVICE=$1; checkvars SERVICE
	say "Restarting $SERVICE..."
	must systemctl restart $SERVICE
}

service_disable() {
	local SERVICE=$1; checkvars SERVICE
	service_is_running $SERVICE && \
		service_stop $SERVICE
	if service_is_installed $SERVICE; then
		say; say "Disabling $SERVICE ..."
		must systemctl disable --now $SERVICE
	else
		say; say "Disabling $SERVICE ... not installed."
	fi
}

service_enable() {
	local SERVICE=$1; checkvars SERVICE
	say; say "Enabling $SERVICE..."
	must systemctl enable --now $SERVICE
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

	say; say "Installing MySQL..."
	service_is_installed mysql && service_stop mysql

	local file=mysql-apt-config_0.8.34-1_all.deb
	wget https://repo.mysql.com//$file
	dpkg_i $file
	rm $file
	apt update
	package_install mysql-server mysql-client
	#sudo systemctl enable --now mysql

	mysql_config default "
# amazing that this is not the default...
bind-address = 127.0.0.1
mysqlx-bind-address = 127.0.0.1

# our binlog is row-based, but we still get an error when creating procs.
log_bin_trust_function_creators = 1

# we only support old auth in the SDK
mysql_native_password=ON
"

	service_start mysql

	say "MySQL install done."
	mysql -e "SELECT VERSION();"

}

install_tarantool() { # tarantool 3.0
	say; say "Installing Tarantool..."
	curl -L https://tarantool.io/release/3/installer.sh | bash
	package_install tarantool tt
	say "Tarantool install done."
}
uninstall_tarantool() {
	service_disable tarantool
	package_uninstall tt tarantool
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

install_journald() {
save "\
[Journal]
SystemMaxUse=20M
" /etc/systemd/journald.conf
	service_restart systemd-journald
}

install_irqbalance() {
	package_install irqbalance
	service_enable irqbalance
}

uninstall_irqbalance() {
	service_disable irqbalance
	package_uninstall irqbalance
}

install_interfaces() { true; }
preinstall_interfaces() {
	NODELETE=1 \
		SRC_DIR=var/machines/$MACHINE/interfaces.d/./. \
		DST_DIR=/etc/network/interfaces.d \
		DST_MACHINE=$MACHINE rsync_dir
}

uninstall_interfaces() {
	empty_dir /etc/network/interfaces.d
}
