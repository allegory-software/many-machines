install_libssl1() {
	os_version
	say -n "Installing OpenSSL 1.1 ... "
	dpkg-query -l libssl1.1 2>/dev/null >/dev/null && { say "already installed."; return 0; }
	[[ $R1 == ubuntu && $R2 == 22.* ]] || { 
		say "NYI for OS: $R1 $R2."
		return 0
	}
	say
	local pkg=libssl1.1_1.1.1f-1ubuntu2.22_amd64.deb
	must wget -q http://nz2.archive.ubuntu.com/ubuntu/pool/main/o/openssl/$pkg
	dpkg_i $pkg
}

machine_set_hostname() { # machine
	local HOST=$1
	checkvars HOST
	say "Setting machine hostname to: $HOST..."
	must hostnamectl set-hostname $HOST
	must sed -i '/^127.0.0.1/d' /etc/hosts
	append "\
127.0.0.1 $HOST $HOST
127.0.0.1 localhost
" /etc/hosts
}

machine_set_timezone() { # tz
	local TZ=$1
	checkvars TZ
	say "Setting machine timezone to: $TZ...."
	must timedatectl set-timezone "$TZ" # sets /etc/localtime and /etc/timezone
}

machine_rename() { # OLD_MACHINE NEW_MACHINE
	local OLD_MACHINE=$1
	local NEW_MACHINE=$2
	checkvars OLD_MACHINE NEW_MACHINE
	machine_set_hostname "$NEW_MACHINE"
}

machine_prepare() {

checkvars MACHINE PACKAGES- DHPARAM- GIT_HOSTS-

say; say "Disabling cloud-init because it resets our changes on reboot..."
[ -d /etc/cloud ] && touch /etc/cloud/cloud-init.disabled

say; machine_set_hostname $MACHINE
say; machine_set_timezone UTC

# remount /proc so we can pass in secrets via cmdline without them leaking.
say; say "Remounting /proc with option to hide command line args..."
must mount -o remount,rw,nosuid,nodev,noexec,relatime,hidepid=2 /proc
# make that permanent...
must sed -i '/^proc/d' /etc/fstab
append "proc  /proc  proc  defaults,nosuid,nodev,noexec,relatime,hidepid=1  0  0" /etc/fstab

say; say "Configuring nginx..."
# add dhparam.pem from mm (dhparam is public).
save "$DHPARAM" /etc/nginx/dhparam.pem
# remove nginx placeholder vhost.
must rm -f /etc/nginx/sites-enabled/default
is_running nginx && nginx -s reload

say; say "Configuring kernel to allow binding to ports < 1024 by any user..."
save 'net.ipv4.ip_unprivileged_port_start=0' \
	/etc/sysctl.d/50-unprivileged-ports.conf
must sysctl --system >/dev/null

#say; install_libssl1
say; install_git
say; mm_update

package_install $PACKAGES
}
