
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

version_glibc() {
	ldd --version | head -1 | awk '{print $NF}'
}

version_cron() {
	package_version cron
}

is_listening() { # IP=|MACHINE= PORT
	local PORT=$1
	[[ $IP ]] || {
		must md_var PUBLIC_IP
		local IP=$R1
	}
	checkvars IP PORT
	nc -zw1 $IP $PORT
}

progress_bar() {
	local total=$1 free=$2
	local width=9
	local n_free
	local n_filled
	if ((total == 0)); then
		n_free=width
		n_filled=0
	else
		n_free=$((width * free / total))
		n_filled=$((width - n_free))
	fi
	local s1=; for ((i = 0; i < n_filled; i++)); do s1+="#"; done
	local s2=; for ((i = 0; i < n_free; i++)); do s2+="."; done
	printf "%s%s\n" "$s1" "$s2"
}

get_RAM_GB()      { cat /proc/meminfo | awk '/MemTotal/      { printf "%.1f\n", $2/(1024*1024) }'; }
get_RAM_KB()      { cat /proc/meminfo | awk '/MemTotal/      { print $2 }'; }
get_FREE_RAM_GB() { cat /proc/meminfo | awk '/MemAvailable/  { printf "%.1f\n", $2/(1024*1024) }'; }
get_FREE_RAM_KB() { cat /proc/meminfo | awk '/MemAvailable/  { print $2 }'; }
get_RAM_RATIO()   { printf "%s/%s G\n" $(get_FREE_RAM_GB) $(get_RAM_GB); }
get_RAM_BAR()     { progress_bar "$(get_RAM_KB)" "$(get_FREE_RAM_KB)"; }

get_SWAP_GB()     { cat /proc/meminfo | awk '/SwapTotal/     { printf "%.1f\n", $2/(1024*1024) }'; }
get_SWAP_KB()     { cat /proc/meminfo | awk '/SwapTotal/     { printf $2 }'; }
get_FREE_SWAP_GB(){ cat /proc/meminfo | awk '/SwapFree/      { printf "%.1f\n", $2/(1024*1024) }'; }
get_FREE_SWAP_KB(){ cat /proc/meminfo | awk '/SwapFree/      { printf $2 }'; }
get_SWAP_RATIO()  { printf "%s/%s G\n" "$(get_FREE_SWAP_GB)" "$(get_SWAP_GB)"; }
get_SWAP_BAR()    { progress_bar "$(get_SWAP_KB)" "$(get_FREE_SWAP_KB)"; }

get_HDD_GB()      { df -l / | awk '(NR > 1) { printf "%.0f\n", $2/(1024*1024) }'; }
get_HDD_KB()      { df -l / | awk '(NR > 1) { print $2 }'; }
get_FREE_HDD_GB() { df -l / | awk '(NR > 1) { printf "%.0f\n", $4/(1024*1024) }'; }
get_FREE_HDD_KB() { df -l / | awk '(NR > 1) { print $4 }'; }
get_HDD_RATIO()   { printf "%s/%s G\n" "$(get_FREE_HDD_GB)" "$(get_HDD_GB)"; }
get_HDD_BAR()     { progress_bar "$(get_HDD_KB)" "$(get_FREE_HDD_KB)"; }

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

get_DIR() {
	DIR=${DIR/#\~/$HOME}
	printf "%s\n" "$DIR"
}
get_DIR_SIZE() {
	checkvars DIR-
	DIR=${DIR/#\~/$HOME}
	dir_lean_size "$DIR"; echo "$R1" | numfmt --to=iec
}

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
rename_hostname() {
	MACHINE=$MACHINE1 install_hostname
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

kernel_config_add() { # FILE LINES
	local FILE=$1
	local LINES=$2
	checkvars FILE LINES-
	say "Adding kernel config rules:"
	say "$LINES"
	say "in file: $FILE ..."
	save "$LINES" /etc/sysctl.d/$FILE
	must sysctl --system >/dev/null
}
kernel_config_remove() { # FILE
	local FILE=$1
	checkvars FILE
	say "Removing kernel config rule file: $FILE ..."
	rm_file /etc/sysctl.d/$FILE
	must sysctl --system >/dev/null
}

install_low_ports() {
	say; say "Configuring kernel to allow binding to ports < 1024 by any user ..."
	kernel_config_add 50-unprivileged-ports.conf 'net.ipv4.ip_unprivileged_port_start=0'
}
uninstall_low_ports() {
	say; say "Removing kernel config that allows binding to ports < 1024 by any user ..."
	kernel_config_remove 50-unprivileged-ports.conf
}

install_tcp_keepalive_tuning() {
	say; say "Tuning TCP keep-alive parameters ..."
	kernel_config_add 50-tcp-keepalive.conf "
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=5
net.ipv4.tcp_keepalive_probes=5
"
}
uninstall_tcp_keepalive_tuning() {
	kernel_config_remove 50-tcp-keepalive.conf
}
