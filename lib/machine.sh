# machine lib: programs running as root on a machine administered by mm.

MI_FMT="%-10s %-5s %-5s %-7s %-7s %-7s %-7s %-30s %-40s\n"
ME_FMT="%-10s %-5s %-5s %-7s %-7s %-7s %-7s %s\n"
machine_info_header() {
	printf "$MI_FMT" MACHINE CPUS CORES RAM FREE HDD FREE OS_VER CPU
}

machine_info_line_fail() { # MACHINE ERROR
	printf "$ME_FMT" $1 - - - - - - "$2"
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

service_version_mysql() {
	has_mysql && query 'select version();'
}
service_version_tarantool() {
	tarantool --version | head -1
}

SS_FMT="%-10s %-12s %-12s %s\n"
service_status_header() {
	printf "$SS_FMT" MACHINE SERVICE STATUS VERSION
}
service_status() { # ]SERVICES]
	[ "$1" ] && SERVICES="$1" || SERVICES="mysql tarantool"
	for SERVICE in $SERVICES; do
		is_running "$SERVICE"
		[ $? == 0 ] && STATUS=RUNNING || STATUS=stopped
		local VERSION=`service_version_$SERVICE 2>/dev/null`
		printf "$SS_FMT" "$MACHINE" "$SERVICE" "$STATUS" "$VERSION"
	done
}
