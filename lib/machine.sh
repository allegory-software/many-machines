# machine lib: programs running as root on a machine administered by mm.

# machine info ---------------------------------------------------------------

MI_FMT="%-5s %-7s %-7s %-9s %-7s %-9s %-30s\n"
machine_list_free_header() {
	printf "$MI_FMT" CPUS CORES RAM FREE DISK FREE OS_VER
}
machine_list_free() {
	local    os_ver="$(lsb_release -sd)"
	local       cps="$(lscpu | sed -n 's/^Core(s) per socket:\s*\(.*\)/\1/p')"
	local   sockets="$(lscpu | sed -n 's/^Socket(s):\s*\(.*\)/\1/p')"
	local     cores="$(expr $sockets \* $cps)"
	local       ram="$(cat /proc/meminfo | awk '/MemTotal/      { printf "%.2fG", $2/(1024*1024)}')"
	local  free_ram="$(cat /proc/meminfo | awk '/MemAvailable/  { printf "%.2fG", $2/(1024*1024)}')"
	local       hdd="$(df -l / | awk '(NR > 1) { printf "%.2fG", $2/(1024*1024)}')"
	local  free_hdd="$(df -l / | awk '(NR > 1) { printf "%.2fG", $4/(1024*1024)}')"
	printf "$MI_FMT" "$sockets" "$cores" "$ram" "$free_ram" "$hdd" "$free_hdd" "$os_ver"
}

machine_list_cpu_header() {
	printf "%-5s %-5s %s\n" CPUS CORES CPU
}
machine_list_cpu() {
	local cps="$(lscpu | sed -n 's/^Core(s) per socket:\s*\(.*\)/\1/p')"
	local sockets="$(lscpu | sed -n 's/^Socket(s):\s*\(.*\)/\1/p')"
	local cores="$(expr $sockets \* $cps)"
	local cpu="$(lscpu | sed -n 's/^Model name:\s*\(.*\)/\1/p')"
	printf "%-5s %-5s %s\n" "$sockets" "$cores" "$cpu"
}

machine_list_cputest_header() {
	printf "%-10s %-5s %-5s %s\n" TIME/CORE CPUS CORES CPU
}
machine_list_cputest() {
	local cps="$(lscpu | sed -n 's/^Core(s) per socket:\s*\(.*\)/\1/p')"
	local sockets="$(lscpu | sed -n 's/^Socket(s):\s*\(.*\)/\1/p')"
	local cores="$(expr $sockets \* $cps)"
	local cpu="$(lscpu | sed -n 's/^Model name:\s*\(.*\)/\1/p')"
	local time="$((time cat </dev/urandom | head -c 50M | gzip >/dev/null) 2>&1 | grep real | awk '{print $2}')"
	printf "%-10s %-5s %-5s %s\n" "$time" "$sockets" "$cores" "$cpu"
}

os_version() {
	[ -f /etc/os-release ] || return 1
	R1=$(. /etc/os-release; printf %s $ID)
	R2=$(. /etc/os-release; printf %s $VERSION_ID)
}

# machine prepare ------------------------------------------------------------

install_openssl1() {
	os_version
	say -n "Installing OpenSSL 1.1 ... "
	dpkg-query -l libssl1.1 2>/dev/null >/dev/null && { say "already installed."; return 0; }
	[[ $R1 == ubuntu ]] || { say "NYI for OS: $R1"; return 0; }
	say
	local pkg=libssl1.1_1.1.1f-1ubuntu2.22_amd64.deb
	must wget -q http://nz2.archive.ubuntu.com/ubuntu/pool/main/o/openssl/$pkg
	dpkg_i $pkg
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
