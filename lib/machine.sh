# machine lib: programs running as root on a machine administered by mm.

# machine info ---------------------------------------------------------------

MI_FMT="%-10s %-5s %-5s %-7s %-7s %-7s %-7s %-30s %-40s\n"
ME_FMT="%-10s %s\n"
machine_info_header() {
	printf "$MI_FMT" MACHINE CPUS CORES RAM FREE HDD FREE OS_VER CPU
}

machine_info_line_fail() { # MACHINE ERROR
	printf "$ME_FMT" "$1" "$2"
}

machine_info_line() {
	local    os_ver="$(lsb_release -sd)"
	local       cpu="$(lscpu | sed -n 's/^Model name:\s*\(.*\)/\1/p')"
	local       cps="$(lscpu | sed -n 's/^Core(s) per socket:\s*\(.*\)/\1/p')"
	local   sockets="$(lscpu | sed -n 's/^Socket(s):\s*\(.*\)/\1/p')"
	local     cores="$(expr $sockets \* $cps)"
	local       ram="$(cat /proc/meminfo | awk '/MemTotal/      { printf "%.1fG", $2/(1024*1024)}')"
	local  free_ram="$(cat /proc/meminfo | awk '/MemAvailable/  { printf "%.1fG", $2/(1024*1024)}')"
	local       hdd="$(df -l / | awk '(NR > 1) { printf "%.1fG", $2/(1024*1024)}')"
	local  free_hdd="$(df -l / | awk '(NR > 1) { printf "%.1fG", $4/(1024*1024)}')"
	printf "$MI_FMT" "$MACHINE" "$sockets" "$cores" "$ram" "$free_ram" "$hdd" "$free_hdd" "$os_ver" "$cpu"
}

# machine prepare ------------------------------------------------------------

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

machine_rename() { # OLD_MACHINE NEW_MACHINE
	local OLD_MACHINE=$1
	local NEW_MACHINE=$2
	checkvars OLD_MACHINE NEW_MACHINE
	machine_set_hostname "$NEW_MACHINE"
}

# services -------------------------------------------------------------------

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

service_version_mysql() {
	has_mysql && mysql --version | awk '{print $3}'
}
service_version_tarantool() {
	tarantool --version | head -1
}
service_version_cron() {
	true
}
SS_FMT="%-10s %-12s %-12s %s\n"
service_status_header() {
	printf "$SS_FMT" MACHINE SERVICE STATUS VERSION
}
service_status() { # ]SERVICES]
	[ "$1" ] && SERVICES="$1" || SERVICES="cron mysql tarantool"
	for SERVICE in $SERVICES; do
		local VERSION
		if VERSION=`service_version_$SERVICE 2>/dev/null`; then
			is_running "$SERVICE"
			[ $? == 0 ] && STATUS=RUNNING || STATUS="not running"
		else
			STATUS=-
			VERSION=-
		fi
		printf "$SS_FMT" "$MACHINE" "$SERVICE" "$STATUS" "$VERSION"
	done
}
