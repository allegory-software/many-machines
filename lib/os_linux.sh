
# machine info ---------------------------------------------------------------

os_version() {
	[ -f /etc/os-release ] || return 1
	R1=$(. /etc/os-release; printf %s $ID)
	R2=$(. /etc/os-release; printf %s $VERSION_ID)
}

version_os() {
	cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2
}

version_kernel() {
	uname -r
}

version_cron() {
	package_version cron
}

is_listening() { # IP=|MACHINE= PORT
	local PORT=$1
	[[ $IP ]] || {
		must machine_var PUBLIC_IP
		local IP=$R1
	}
	checkvars IP PORT
	nc -zw1 $IP $PORT
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

# installers -----------------------------------------------------------------

install_disable_cloudinit() {
	say; say "Disabling cloud-init because it resets our changes on reboot ..."
	[[ -d /etc/cloud ]] || return 0
	touch /etc/cloud/cloud-init.disabled
}
uninstall_disable_cloudinit() {
	say; say "Removing cloud-init.disabled ..."
	[[ -d /etc/cloud ]] || return 0
	rm_file /etc/cloud/cloud-init.disabled
}

set_hostname() { # HOST
	local HOST=$1
	checkvars HOST
	say; say "Setting machine hostname to: '$HOST' ..."
	must hostnamectl set-hostname $HOST
	must sed -i '/^127.0.0.1/d' /etc/hosts
	append "\
127.0.0.1 $HOST $HOST
127.0.0.1 localhost
" /etc/hosts
}

install_hostname() {
	set_hostname $MACHINE
}
uninstall_hostname() {
	set_hostname local
}

install_timezone() {
	checkvars TIMEZONE
	say; say "Setting machine timezone to: '$TIMEZONE' ...."
	must timedatectl set-timezone "$TIMEZONE" # sets /etc/localtime and /etc/timezone
}
uninstall_timezone() { true; }

# remount /proc so we can pass in secrets via cmdline without them leaking.
install_secure_proc() {
	say; say "Remounting /proc with option to hide command line args ..."
	must mount -o remount,rw,nosuid,nodev,noexec,relatime,hidepid=2 /proc
	# make that permanent...
	must sed -i '/^proc/d' /etc/fstab
	append "proc  /proc  proc  defaults,nosuid,nodev,noexec,relatime,hidepid=1  0  0" /etc/fstab
}
uninstall_secure_proc() {
	# TODO
	true
}

install_low_ports() {
	say; say "Configuring kernel to allow binding to ports < 1024 by any user ..."
	save 'net.ipv4.ip_unprivileged_port_start=0' \
		/etc/sysctl.d/50-unprivileged-ports.conf
	must sysctl --system >/dev/null
}
uninstall_low_ports() {
	say; say "Removing kernel config that allows binding to ports < 1024 by any user ..."
	rm_file /etc/sysctl.d/50-unprivileged-ports.conf
	must sysctl --system >/dev/null
}
