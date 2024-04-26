# machine lib: programs running as root on a machine administered by mm.

# machine info ---------------------------------------------------------------

is_listening() { # IP=|MACHINE= PORT
	local PORT=$1
	[[ $IP ]] || {
		must machine_var PUBLIC_IP
		local IP=$R1
	}
	checkvars IP PORT
	nc -zw1 $IP $PORT
}

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

# versions -------------------------------------------------------------------

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
		VERSION=`version_$SERVICE 2>/dev/null`
		is_running "$SERVICE" && STATUS=UP || STATUS=DOWN!
		printf "%s\n" $MACHINE $SERVICE "${STATUS:--}" "${VERSION:--}"
	done
}
