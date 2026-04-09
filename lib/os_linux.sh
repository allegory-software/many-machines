
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

# TODO: remove this after we make the list of versioned components explicit rather than implicit.
version_cron() {
	package_version cron
}

open_ports() { # IP=|MACHINE= [UDP=1] PORTS ...
	local PORTS="$@"
	[[ $IP ]] || {
		must md_var PUBLIC_IP
		local IP=$R1
	}
	checkvars IP PORTS-
	nc -zv -w 1 ${UDP:+-u} $IP $PORTS 2>&1 | awk '/succeeded/ {print $4}' | tr '\n' ' '
}

is_listening() { # IP=|MACHINE= PORT
	local PORT=$1
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

_df() { [[ -d $MOUNT ]] && df -l $MOUNT || { echo; echo 0.0; }; }
get_DISK_GB()      { _df | awk '(NR > 1) {printf "%.0f\n", $2/(1024*1024)}'; }
get_DISK_KB()      { _df | awk '(NR > 1) {print $2}'; }
get_FREE_DISK_GB() { _df | awk '(NR > 1) {printf "%.0f\n", $4/(1024*1024)}'; }
get_FREE_DISK_KB() { _df | awk '(NR > 1) {print $4}'; }
get_DISK_RATIO()   { printf "%s/%s G\n" "$(get_FREE_DISK_GB)" "$(get_DISK_GB)"; }
get_DISK_BAR()     { progress_bar "$(get_DISK_KB)" "$(get_FREE_DISK_KB)"; }

get_D00_GB()      { MOUNT=/ get_DISK_GB; }
get_D00_KB()      { MOUNT=/ get_DISK_KB; }
get_FREE_D00_GB() { MOUNT=/ get_FREE_DISK_GB; }
get_FREE_D00_KB() { MOUNT=/ get_DISK_KB; }
get_D00_RATIO()   { MOUNT=/ get_DISK_RATIO; }
get_D00_BAR()     { MOUNT=/ get_DISK_BAR; }

DISK_DATA=/home
get_D01_GB()      { MOUNT=$DISK_DATA get_DISK_GB; }
get_D01_KB()      { MOUNT=$DISK_DATA get_DISK_KB; }
get_FREE_D01_GB() { MOUNT=$DISK_DATA get_FREE_DISK_GB; }
get_FREE_D01_KB() { MOUNT=$DISK_DATA get_DISK_KB; }
get_D01_RATIO()   { MOUNT=$DISK_DATA get_DISK_RATIO; }
get_D01_BAR()     { MOUNT=$DISK_DATA get_DISK_BAR; }

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
	sysbench cpu --time=2 --threads=$(nproc) run | awk '/events per second/ {print $4}'
	#(time head -c 50M /dev/zero | gzip >/dev/null) 2>&1 | grep real | awk '{print $2}'
	#(time cat </dev/urandom | head -c 50M | gzip >/dev/null) 2>&1 | grep real | awk '{print $2}'
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
get_DIR_SHA() {
	checkvars DIR-
	DIR=${DIR/#\~/$HOME}
	dir_sha "$DIR"; echo "$R1"
}

# installers -----------------------------------------------------------------

install_cloudinit() {
	say; say "Removing cloud-init.disabled ..."
	[[ -d /etc/cloud ]] || return 0
	rm_file /etc/cloud/cloud-init.disabled
}
uninstall_cloudinit() {
	say; say "Disabling cloud-init because it resets our changes on reboot ..."
	[[ -d /etc/cloud ]] || return 0
	touch /etc/cloud/cloud-init.disabled
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
_remount_proc() { # HIDEPID
	say; say "Remounting /proc with hidepid=$1 ..."
	must mount -o remount,rw,nosuid,nodev,noexec,relatime,hidepid=$1 /proc
	# make that permanent...
	must sed -i '/^proc/d' /etc/fstab
	append "proc  /proc  proc  defaults,nosuid,nodev,noexec,relatime,hidepid=$1  0  0" /etc/fstab
}
install_secure_proc() {
	_remount_proc 2
}
uninstall_secure_proc() {
	_remount_proc 0
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

install_tcp_tuning() {
	# detect and close sockets on dead peers sooner (~85s).
	say; say "Tuning TCP keep-alive parameters ..."
	kernel_config_add 50-tcp-keepalive.conf "
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=5
net.ipv4.tcp_keepalive_probes=5
"
}
uninstall_tcp_tuning() {
	kernel_config_remove 50-tcp-keepalive.conf
}

install_secure_ssh() {
	say; say "Hardening SSH daemon ..."
	save "\
# require SSH keys; password auth is off
PasswordAuthentication no
# allow key-based root login but block password-based root login
PermitRootLogin prohibit-password
# don't forward the X display (attack surface, almost never needed over SSH)
X11Forwarding no
# disconnect after this many failed auth attempts per connection
MaxAuthTries 10
" /etc/ssh/sshd_config.d/50-hardening.conf
	service_restart ssh
}
uninstall_secure_ssh() {
	rm_file /etc/ssh/sshd_config.d/50-hardening.conf
	service_restart ssh
}

install_secure_kernel() {
	say; say "Hardening kernel parameters ..."
	kernel_config_add 50-secure-kernel.conf "
# hide kernel ring buffer (boot messages, driver info) from unprivileged users
kernel.dmesg_restrict=1
# hide kernel symbol addresses from unprivileged users (2=always hidden)
kernel.kptr_restrict=2
"
}
uninstall_secure_kernel() {
	kernel_config_remove 50-secure-kernel.conf
}

install_secure_net() {
	say; say "Hardening network parameters ..."
	kernel_config_add 50-secure-net.conf "
# drop packets whose source address is unreachable via the incoming interface
# (prevents IP spoofing; set on all interfaces and the default for new ones)
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
# ignore ICMP redirects (routers telling us to use a different route)
# (prevents route-poisoning MITM attacks)
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
# don't send ICMP redirects (we're not a router)
net.ipv4.conf.all.send_redirects=0
# ignore packets that carry their own route (source routing)
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
# use SYN cookies when the SYN backlog fills up (mitigates SYN flood attacks)
net.ipv4.tcp_syncookies=1
"
}
uninstall_secure_net() {
	kernel_config_remove 50-secure-net.conf
}

install_secure_fs() {
	say; say "Hardening filesystem parameters ..."
	kernel_config_add 50-secure-fs.conf "
# block following symlinks in sticky world-writable dirs unless owner matches
# (mitigates TOCTOU race attacks in /tmp and similar dirs)
fs.protected_symlinks=1
# block hardlinking to files you don't own
# (mitigates privilege escalation via suid/sgid file hardlinks)
fs.protected_hardlinks=1
"
}
uninstall_secure_fs() {
	kernel_config_remove 50-secure-fs.conf
}

install_gdu() {
	sayn "Installing gdu latest ... "
	must curl -s -L https://github.com/dundee/gdu/releases/latest/download/gdu_linux_amd64-x.tgz | tar xzO gdu_linux_amd64-x > /usr/local/bin/gdu
	must chmod 755 /usr/local/bin/gdu
	say OK
}
uninstall_gdu() {
	rm_file /usr/local/bin/gdu
}

install_goful() {
	sayn "Installing goful latest ... "
	must curl -s -L https://github.com/anmitsu/goful/releases/latest/download/goful_linux_x86_64.tar.gz | tar xzO goful > /usr/local/bin/goful
	must chmod 755 /usr/local/bin/goful
	say OK
}
uninstall_goful() {
	rm_file /usr/local/bin/goful
}

install_lazygit() {
	local VER=`curl -sI https://github.com/jesseduffield/lazygit/releases/latest | grep -i location | awk -F'/' '{print $NF}' | tr -d '\rv'`
	checkvars VER
	sayn "Installing lazygit $VER ... "
	local file=lazygit_${VER}_linux_x86_64.tar.gz
	must curl -s -L https://github.com/jesseduffield/lazygit/releases/download/v$VER/$file | tar xzO lazygit > /usr/local/bin/lazygit
	must chmod 755 /usr/local/bin/lazygit
	say OK
}
uninstall_lazygit() {
	rm_file /usr/local/bin/lazygit
}

install_sensors() {
	# kernel module to read RAM temperature sensor
	modprobe spd5118
	save spd5118 /etc/modules-load.d/spd5118.conf
	# kernel module to read CPU temperature sensor
	modprobe coretemp
	save coretemp /etc/modules-load.d/coretemp.conf
}
