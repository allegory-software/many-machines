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
	service_stop avahi-daemon.socket
	service_stop avahi-daemon
}

install_iptables() {
	service_enable netfilter-persistent
}
uninstall_iptables() {
	service_disable netfilter-persistent
	iptables -F
}

install_nftables() {
	save '#!/usr/sbin/nft -f
flush ruleset
include "/etc/nftables.d/*.conf"
' /etc/nftables.conf
	save "\
table inet filter {
	chain input {
		type filter hook input priority 0; policy drop;

		iif lo accept

		ct state established,related accept

		ip protocol icmp accept
		ip6 nexthdr icmpv6 accept

		tcp dport { ${TCP_PORTS//[[:space:]]/,} } accept
		udp dport { ${UDP_PORTS//[[:space:]]/,} } accept
	}
	chain forward {
		type filter hook forward priority 0; policy drop;

		ct state established,related accept
	}
}
" /etc/nftables.d/10-filter.conf
	nft -f /etc/nftables.conf
	service_enable nftables
}
uninstall_nftables() {
	rm_file /etc/nftables.d/10-filter.conf
	service_disable nftables
	nft flush ruleset
}

install_journald() {
	save "\
[Journal]
SystemMaxUse=200M
" /etc/systemd/journald.conf.d/mm.conf
	service_restart systemd-journald
}
uninstall_journald() {
	rm_file /etc/systemd/journald.conf.d/mm.conf
	service_restart systemd-journald
}

install_irqbalance() {
	package_install irqbalance
	service_enable irqbalance
}

uninstall_irqbalance() {
	package_uninstall irqbalance
}

install_networkd() {
	service_enable systemd-networkd
	service_disable networking
	save "
[Service]
ExecStart=
ExecStart=/lib/systemd/systemd-networkd-wait-online --any --timeout=10
" /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
	systemctl daemon-reload
}

uninstall_networkd() {
	service_enable networking
	service_disable systemd-networkd
}

install_interfaces() {
	empty_dir /etc/systemd/network
	local NAME; for NAME in $INTERFACES; do
		local -n CONFIG=INTERFACE_${NAME^^}
		save "$CONFIG" /etc/systemd/network/${NAME}.network
	done
	networkctl reload
}

uninstall_interfaces() {
	empty_dir /etc/systemd/network
	networkctl reload
}

install_ups_apc() {

	package_install apcupsd

	local c=/etc/apcupsd/apcupsd.conf
	replace_lines '^DEVICE'       'DEVICE'          $c  # it's a usb device not ttyS0
	replace_lines '^BATTERYLEVEL' 'BATTERYLEVEL 40' $c  # 5% is too low for uncalibrated battery
	replace_lines '^SLEEP'        'SLEEP 20'        $c  # 20s might be too low

	save '#!/bin/bash
printf "%s | %s\n" "$(date)" "doshutdown script" >> /var/log/apccontrol.log
mm . hibernate-pc
NOTHIS=1 mm '$UPS_MACHINES' shutdown
' /etc/apcupsd/doshutdown root 755

	service_enable apcupsd
}

uninstall_ups_apc() {
	package_uninstall apcupsd
}

install_wireguard() {

	package_install wireguard

	local PEERS
	for NAME in $WG_CLIENTS; do
		local -n ADDRESS=WGC_${NAME^^}_ADDRESS
		local -n KEY=WGC_${NAME^^}_KEY
		PEERS="\
$PEERS
[Peer]
AllowedIPs = $ADDRESS
PublicKey = $KEY
PersistentKeepalive = 25
"
	done

	save "\
[Interface]
Address = $WG_ADDRESS
ListenPort = $WG_PORT
PrivateKey = $WG_KEY
SaveConfig = false
$PEERS
" /etc/wireguard/wg0.conf root 600

	kernel_config_add 50-forward-wg.conf "
# required for wireguard to route traffic between VPN clients and the internet
net.ipv4.ip_forward=1
"

	save "\
table ip nat {
	chain POSTROUTING {
		type nat hook postrouting priority srcnat; policy accept;
		oif enp1s0 ip saddr 10.2.0.0/16 masquerade
	}
}
# allow VPN clients to be forwarded out; return traffic is covered by established/related
add rule inet filter forward iif \"wg0\" accept
" /etc/nftables.d/20-nat-wg.conf
	service_is_installed nftables && nft -f /etc/nftables.conf

	service_restart wg-quick@wg0
}

uninstall_wireguard() {
	service_stop wg-quick@wg0
	package_uninstall wireguard
	rm_file /etc/wireguard/wg0.conf
	kernel_config_remove 50-forward-wg.conf
	rm_file /etc/nftables.d/20-nat-wg.conf
	service_is_installed nftables && nft -f /etc/nftables.conf
}

uu_file=/etc/apt/apt.conf.d/50unattended-upgrades
au_file=/etc/apt/apt.conf.d/20auto-upgrades

install_unattended_upgrades() {
	package_install unattended-upgrades
	[[ -f $uu_file.disabled ]] || mv_file $uu_file $uu_file.disabled

	save "\
Unattended-Upgrade::Allowed-Origins {
	\"${distro_id}:${distro_codename}-security\";
" $uu_file

	save "\
APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Unattended-Upgrade \"1\";
" $au_file

}

uninstall_unattended_upgrades() {
	[[ -f $uu_file.disabled ]] && mv_file $uu_file.disabled $uu_file
	rm_file $au_file
	package_uninstall unattended-upgrades
}
