# machine lib: programs running as root on a machine administered by mm.

is_listening() {
	local PORT=$1
	checkvars PUBLIC_IP PORT
	nc -zw1 $PUBLIC_IP $1
}

# machine info ---------------------------------------------------------------

get_RAM()         { cat /proc/meminfo | awk '/MemTotal/      { printf "%.2fG\n", $2/(1024*1024) }'; }
get_FREE_RAM()    { cat /proc/meminfo | awk '/MemAvailable/  { printf "%.2fG\n", $2/(1024*1024) }'; }
get_FREE_RAM_KB() { cat /proc/meminfo | awk '/MemAvailable/  { print $2 }'; }
get_SWAP()        { cat /proc/meminfo | awk '/SwapTotal/     { printf "%.2fG\n", $2/(1024*1024) }'; }
get_FREE_SWAP()   { cat /proc/meminfo | awk '/SwapFree/      { printf "%.2fG\n", $2/(1024*1024) }'; }
get_HDD()         { df -l / | awk '(NR > 1) { printf "%.2fG\n", $2/(1024*1024) }'; }
get_FREE_HDD()    { df -l / | awk '(NR > 1) { printf "%.2fG\n", $4/(1024*1024) }'; }
get_FREE_HDD_KB() { df -l / | awk '(NR > 1) { print $4 }'; }

get_CPU()         { lscpu | sed -n 's/^Model name:\s*\(.*\)/\1/p'; }
get_CPUS()        { lscpu | sed -n 's/^Socket(s):\s*\(.*\)/\1/p'; }
get_CPS()         { lscpu | sed -n 's/^Core(s) per socket:\s*\(.*\)/\1/p'; }
get_CORES()       {
	local cps=`get_CPS`
	local sockets=`get_CPUS`
	printf "%d\n" $((sockets * cps))
}
get_CPU_CACHE()   { awk -F: '/cache size/ {cache=$2} END {print cache}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//'; }
get_CPU_FREQ()    { awk -F'[ :]' '/cpu MHz/ {printf "%.1f GHz\n", $4/1024; exit}' /proc/cpuinfo; }
get_AES()         { grep -iq 'aes' /proc/cpuinfo && echo "YES"; }

get_UPTIME()   {
	awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%dd%dh%dm\n",a,b,c)}' /proc/uptime
}

get_CPUTEST()  {
	(time cat </dev/urandom | head -c 50M | gzip >/dev/null) 2>&1 | grep real | awk '{print $2}'
}

get_ISP()     { wget -q -T10 -O- ipinfo.io/org; }
get_CITY()    { wget -q -T10 -O- ipinfo.io/city; }
get_COUNTRY() { wget -q -T10 -O- ipinfo.io/country; }
get_REGION()  { wget -q -T10 -O- ipinfo.io/region; }

os_version() {
	[ -f /etc/os-release ] || return 1
	R1=$(. /etc/os-release; printf %s $ID)
	R2=$(. /etc/os-release; printf %s $VERSION_ID)
}

machine_deploys() {
	local USER
	for USER in `ls -1 /home`; do
		[[ -L /home/$USER/app ]] && printf "%s\n" $USER
	done
}

get_DEPLOYS() {
	local s=`machine_deploys`
	printf "%s\n" "${s//$'\n'/ }"
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

# components -----------------------------------------------------------------

package_version() { # PACKAGE
	local PACKAGE=$1
	checkvars PACKAGE
	grep -A 10 "^Package: $PACKAGE\$" /var/lib/dpkg/status | grep "^Version:" | cut -d' ' -f2
}

version_os() {
	cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2
}
version_kernel() {
	uname -r
}
version_mm() {
	(
	must cd /opt/mm
	must git rev-parse --short HEAD
	)
}
version_mysql() {
	has_mysql && mysql --version | awk '{print $3}'
}
version_tarantool() {
	tarantool --version | head -1
}
version_cron() {
	# this is too slow...
	#apt show cron 2>/dev/null | grep Version: | cut -d' ' -f2
	package_version cron
}
version_acme() {
	/root/.acme.sh/acme.sh -v | tail -1
}
version_nginx() {
	nginx -v 2>&1 | awk '{print $3}'
}

component_version() { # ["COMPONENT1 ..."]
	local COMPS; [[ $1 ]] && COMPS=$1 || { functions_with_prefix version_; COMPS=$R1; }
	for COMP in $COMPS; do
		local VERSION=`version_$COMP 2>/dev/null`
		printf "%s\n" $MACHINE $COMP "${VERSION:--}"
	done
}

# services -------------------------------------------------------------------

is_running() {
	systemctl -q is-active "$1"
}

service_start() {
	local SERVICE=$1; checkvars SERVICE
	say "Starting $SERVICE..."
	must service "$SERVICE" start
}

service_stop() {
	local SERVICE=$1; checkvars SERVICE
	say "Stopping $SERVICE..."
	must service "$SERVICE" stop
}

service_status() { # ["SERVICE1 ..."]
	[[ $1 ]] && SERVICES=$1
	for SERVICE in $SERVICES; do
		local VERSION
		if VERSION=`version_$SERVICE 2>/dev/null`; then
			is_running "$SERVICE" && STATUS=UP || STATUS=DOWN!
		fi
		printf "%s\n" $MACHINE $SERVICE "${STATUS:--}" "${VERSION:--}"
	done
}
