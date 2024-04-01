
machine_cores() {
	local      cps="$(lscpu | sed -n 's/^Core(s) per socket:\s*\(.*\)/\1/p')"
	local  sockets="$(lscpu | sed -n 's/^Socket(s):\s*\(.*\)/\1/p')"
	echo "    cores $(expr $sockets \* $cps)"
}

machine_info() {
	echo "   os_ver $(lsb_release -sd)"
	echo "mysql_ver $(has_mysql && query 'select version();')"
	echo "      cpu $(lscpu | sed -n 's/^Model name:\s*\(.*\)/\1/p')"
	local      cps="$(lscpu | sed -n 's/^Core(s) per socket:\s*\(.*\)/\1/p')"
	local  sockets="$(lscpu | sed -n 's/^Socket(s):\s*\(.*\)/\1/p')"
	echo "    cores $(expr $sockets \* $cps)"
	echo "      ram $(cat /proc/meminfo | awk '/MemTotal/ {$2*=1024; printf "%.0f",$2}')"
	echo "      hdd $(df -l / | awk '(NR > 1) {$2*=1024; printf "%.0f",$2}')"
}

machine_vars_upload() {
	MACHINE="$1"; checkvar MACHINE
	machine_vars "$MACHINE"; VARS="$R1"
	say "Uploading env vars to $MACHINE in /root/.mm/vars ..."; indent
	echo "$VARS" | ssh_to "$MACHINE" bash -c "mkdir -p /root/.mm; cat > /root/.mm/vars"
	outdent
}

machine_set_hostname() { # machine
	local HOST="$1"
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
	local TZ="$1"
	checkvars TZ
	say "Setting machine timezone to: $TZ...."
	must timedatectl set-timezone "$TZ" # sets /etc/localtime and /etc/timezone
}

acme_sh() {
	local cmd_args="/root/.acme.sh/acme.sh --config-home /root/.acme.sh.etc"
	run $cmd_args "$@"
	local ret=$?; [ $ret == 2 ] && ret=0 # skipping gets exit code 2.
	[ $ret == 0 ] || die "$cmd_args $@ [$ret]"
}

acme_check() {
	say "Checking SSL certificate with acme.sh ... "
	acme_sh --cron
}

tarantool_install() { # tarantool 2.10
	say "Instlaling Tarantool..."
	must curl -L https://tarantool.io/BsbZsuW/release/2/installer.sh | bash
	apt_get_install tarantool
	say "Tarantool install done."
}

machine_rename() { # OLD_MACHINE NEW_MACHINE
	local OLD_MACHINE=$1
	local NEW_MACHINE=$2
	checkvars OLD_MACHINE NEW_MACHINE
	machine_set_hostname "$NEW_MACHINE"
}

machine_deploys() {
	local USER
	for USER in `ls -1 /home`; do
		[ -f "/home/$USER/.deploy" ] && echo $USER
	done
}

is_running() {
	systemctl -q is-active "$1"
}

service_start() {
	local SERVICE="$1"; checkvars SERVICE
	say "Starting $SERVICE..."
	must service "$SERVICE" start
}

service_stop() {
	local SERVICE="$1"; checkvars SERVICE
	say "Stopping $SERVICE..."
	must service "$SERVICE" stop
}
