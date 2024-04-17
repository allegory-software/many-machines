# machine lib: programs running as root on a machine administered by mm.

# machine info ---------------------------------------------------------------

get_OS_VER()   { lsb_release -sd; }
get_RAM()      { cat /proc/meminfo | awk '/MemTotal/      { printf "%.2fG\n", $2/(1024*1024)}'; }
get_FREE_RAM() { cat /proc/meminfo | awk '/MemAvailable/  { printf "%.2fG\n", $2/(1024*1024)}'; }
get_HDD()      { df -l / | awk '(NR > 1) { printf "%.2fG\n", $2/(1024*1024)}'; }
get_FREE_HDD() { df -l / | awk '(NR > 1) { printf "%.2fG\n", $4/(1024*1024)}'; }
get_CPU()      { lscpu | sed -n 's/^Model name:\s*\(.*\)/\1/p'; }
get_CPUS()     { lscpu | sed -n 's/^Socket(s):\s*\(.*\)/\1/p'; }
get_CPS()      { lscpu | sed -n 's/^Core(s) per socket:\s*\(.*\)/\1/p'; }
get_CORES()    {
	local cps="$(get_CPS)"
	local sockets="$(get_CPUS)"
	expr $sockets \* $cps
}
get_CPUTEST()  {
	(time cat </dev/urandom | head -c 50M | gzip >/dev/null) 2>&1 | grep real | awk '{print $2}'
}

os_version() {
	[ -f /etc/os-release ] || return 1
	R1=$(. /etc/os-release; printf %s $ID)
	R2=$(. /etc/os-release; printf %s $VERSION_ID)
}

machine_deploys() {
	local USER
	for USER in `ls -1 /home`; do
		[ -L "/home/$USER/app" ] && echo $USER
	done
}

# machine prepare ------------------------------------------------------------

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
service_version_nginx() {
	nginx -v 2>&1 | awk '{print $3}'
}
SS_FMT="%-10s %-12s %-12s %s\n"
service_status_header() {
	printf "$SS_FMT" MACHINE SERVICE STATUS VERSION
}
service_status() { # [SERVICES]
	[ "$1" ] && SERVICES="$1" || SERVICES="nginx cron mysql tarantool"
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
