# deploy lib: programs for deployments admin, running as root on a machine administered by mm.

# deploy app module ----------------------------------------------------------

APP_SUBDIR=${APP_SUBDIR:-.} # app directory relative to checkout

try_app() {
	checkvars DEPLOY APP APP_SUBDIR
	VARS="DEBUG VERBOSE" run_as $DEPLOY \
		/home/$DEPLOY/app/$APP_SUBDIR/$APP "$@"; local ret=$?
	return $ret
}

app() {
	must try_app "$@"
}

_deploy_version() {
	must pushd /home/$DEPLOY/$1
	run_as $DEPLOY git rev-parse --short HEAD
	popd
}
deploy_version_app() { _deploy_version app; }
deploy_version_sdk() {
	checkvars SDK_SUBDIR?
	if [[ $SDK_SUBDIR ]]; then
		_deploy_version app/$SDK_SUBDIR
	fi
}

get_APP_WANT() {
	checkvars REPO APP_VERSION
	local s=$(git ls-remote $REPO refs/heads/$APP_VERSION)
	echo ${s:0:7}
}

get_APP_DEPL() { deploy_version_app; }
get_SDK_DEPL() { deploy_version_sdk; }

get_APP_LATEST() {
	[[ `get_APP_WANT` == `get_APP_DEPL` ]] && \
		echo ${LIGHTGRAY}yes$ENDCOLOR || \
		echo ${LIGHTRED}NO!$ENDCOLOR
}

# app service as daemon ------------------------------------------------------
# not used since it doesn't start automatically on reboot this way.

deploy_is_running_app_daemon_fast() {
	catfile /home/$DEPLOY/app/$APP_SUBDIR/$APP.pid
	local pid=$R1
	[[ $pid ]] && kill -0 $pid 2>/dev/null || return 1
	local cmdline; IFS=$'\0' mapfile -d '' -t cmdline < /proc/$pid/cmdline
	[[ "${cmdline[0]}" == *luajit* ]] || return 1
	[[ "${cmdline[1]}" == *$APP* ]] || return 1
	return 0
}
deploy_is_running_app_daemon() {
	checkvars DEPLOY APP APP_SUBDIR
	[[ -d /home/$DEPLOY/app/$APP_SUBDIR ]] || return
	deploy_is_running_app_daemon_fast
	#try_app running
}

deploy_start_app_daemon() {
	say "Starting the app..."
	must app start
	must app status
}

deploy_stop_app_daemon() {
	deploy_is_running_app_daemon && must app stop
}

# app service as systemd service ---------------------------------------------

# APP_PROCESSES instances of the $DEPLOY@.service template, numbered from 1.
deploy_app_services() { # -> R1=(service ...)
	local n=${APP_PROCESSES:-1} # app process count
	[[ $n =~ ^[1-9][0-9]*$ ]] || die "APP_PROCESSES must be a positive integer"
	R1=()
	local i
	for ((i = 1; i <= n; i++)); do
		R1+=($DEPLOY@$i.service)
	done
}

# run COMMAND ARGS... SERVICE for instances 1..APP_PROCESSES, or with LOADED=1
# for every instance systemd has loaded, including ones beyond APP_PROCESSES.
# stop at the first failure.
each_deploy_app_service() { # [LOADED=1] COMMAND ARGS...
	local -a services # instance service names
	if [[ $LOADED ]]; then
		services=($(systemctl list-units --all --plain --no-legend \
			"$DEPLOY@*.service" | awk '{print $1}'))
	else
		deploy_app_services
		services=("${R1[@]}")
	fi
	local service
	for service in "${services[@]}"; do
		"$@" $service || return
	done
}

deploy_is_running_app_service() {
	each_deploy_app_service service_is_running
}
deploy_start_app_service() {
	each_deploy_app_service service_start
}
deploy_stop_app_service() {
	LOADED=1 each_deploy_app_service service_stop
}
deploy_restart_app_service() {
	each_deploy_app_service service_restart
}

deploy_install_app_service() {
	checkvars DEPLOY APP APP_SUBDIR
	[[ $HTTP_PORT && ${APP_PROCESSES:-1} != 1 ]] \
		&& die "APP_PROCESSES > 1 requires HTTP_UNIX_SOCKET"
	# single-process unit of earlier versions: remove it.
	if [[ -f /etc/systemd/system/$DEPLOY.service ]]; then
		service_disable $DEPLOY.service
		rm_file /etc/systemd/system/$DEPLOY.service
	fi
	LOADED=1 each_deploy_app_service service_disable
	save "
[Unit]
Description=$DEPLOY %i
After=multi-user.target
After=network.target

# try restarting for 60s
StartLimitIntervalSec=60

# try restarting 3 times
StartLimitBurst=3

[Service]
Type=simple
User=$DEPLOY
Group=$DEPLOY

ExecStart=/home/$DEPLOY/app/$APP_SUBDIR/$APP -q run
Environment=APP_INSTANCE=%i
${HTTP_UNIX_SOCKET:+Environment=HTTP_UNIX_SOCKET=/run/$DEPLOY/http-%i.sock}
WorkingDirectory=/home/$DEPLOY/app/$APP_SUBDIR
StandardOutput=null
# app runs in quiet mode so only fatal errors go to journal.
StandardError=journal

# restart only if exit code != 0
Restart=on-failure
# wait 1s before restarting
RestartSec=1

### protection: filesystem
#
# entire fs is r/o except /dev, /proc, /sys, ReadWritePaths=
ProtectSystem=strict
# mount a private /tmp and /var/tmp
PrivateTmp=yes
# replace with empty tmpfs: /home, /root, /run/user, then rebind app dirs
ProtectHome=tmpfs
BindReadOnlyPaths=/home/$DEPLOY/app
ReadWritePaths=/home/$DEPLOY/app/$APP_SUBDIR/var /run/$DEPLOY
NoExecPaths=/home/$DEPLOY/app/$APP_SUBDIR/var
UMask=0027

### protection: privileges
#
NoNewPrivileges=yes
PrivateDevices=yes
ProtectClock=yes
ProtectHostname=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectProc=invisible
ProcSubset=pid
CapabilityBoundingSet=
AmbientCapabilities=
RestrictSUIDSGID=yes
LockPersonality=yes
KeyringMode=private
RemoveIPC=yes
RestrictNamespaces=yes
RestrictRealtime=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

[Install]
WantedBy=multi-user.target

" /etc/systemd/system/$DEPLOY@.service

	systemctl daemon-reload
	each_deploy_app_service service_enable
}

deploy_uninstall_app_service() {
	checkvars DEPLOY APP
	LOADED=1 each_deploy_app_service service_disable
	rm_file /etc/systemd/system/$DEPLOY@.service
}

# app service and module -----------------------------------------------------

deploy_is_running_app() { deploy_is_running_app_service; }
deploy_start_app() { deploy_start_app_service; }
deploy_stop_app() { deploy_stop_app_service; }
deploy_restart_app() { deploy_restart_app_service; }

get_APP_STATUS() {
	deploy_is_running_app && \
		echo ${LIGHTGRAY}up$ENDCOLOR || \
		echo ${LIGHTRED}DOWN!$ENDCOLOR
}

deploy_install_app() {
	checkvars DEPLOY REPO APP APP_VERSION APP_SUBDIR SDK_SUBDIR?
	(deploy_stop_app)
	if [[ $FAST && $SDK_SUBDIR && $SDK_SUBDIR != . ]]; then
		local SUBMODULES=$SDK_SUBDIR # SDK submodule path
	fi
	git_clone_for $DEPLOY $REPO /home/$DEPLOY/app "$APP_VERSION"
	deploy_gen_conf
	[[ ! $FAST ]] && {
		say "Installing $APP ..."
		must app install forealz
	}
	deploy_start_app
}

deploy_install_app_fast() {
	FAST=1 deploy_install_app "$@"
}

deploy_uninstall_app() {
	deploy_stop_app
	checkvars DEPLOY APP
	rm_dir /home/$DEPLOY/app
}

deploy_rename_app() {
	DEPLOY=$DEPLOY1 deploy_gen_conf
}

deploy_gen_conf() {
	checkvars MACHINE DEPLOY APP APP_SUBDIR
	local conf # generated app configuration file
	conf=/home/$DEPLOY/app/$APP_SUBDIR/var/${APP}.conf
	local HOST=${DOMAIN:-$PUBLIC_IP}

	must dry run_as $DEPLOY mkdir -p /home/$DEPLOY/app/$APP_SUBDIR/var
	save "\
--deploy vars
deploy = '$DEPLOY'
machine = '$MACHINE'
${ENV:+env = '$ENV'}
${APP_VERSION:+version = '$APP_VERSION'}

--custom vars
http_host = '*' --trust host header
x_forwarded_headers = true
${HTTP_UNIX_SOCKET:+http_unix_socket_perms = '0660'}
${HTTP_UNIX_SOCKET:+http_compress = false}
${HTTP_PORT:+http_port = $HTTP_PORT}
${SMTP_HOST:+smtp_host = '$SMTP_HOST'}
${SMTP_HOST:+smtp_user = '$SMTP_USER'}
${SMTP_HOST:+smtp_pass = '$SMTP_PASS'}
${NOREPLY_EMAIL:+noreply_email = '$NOREPLY_EMAIL'}
${DEV_EMAIL:+dev_email = '$DEV_EMAIL'}
${DEFAULT_COUNTRY:+default_country = '$DEFAULT_COUNTRY'}
${SESSION_COOKIE_SECURE_FLAG:+session_cookie_secure_flag = $SESSION_COOKIE_SECURE_FLAG}

log_host = '127.0.0.1'
log_port = 5555
https_addr = false
" $conf $DEPLOY
}

machine_deploys() {
	local USER
	R1=()
	for USER in `ls -1 /home`; do
		[[ -d /home/$USER/app ]] && R1+=($USER)
	done
	R1="${R1[*]}"
}

get_DEPLOYS() {
	machine_deploys
	printf "%s\n" "$R1"
}

# deploy user module ---------------------------------------------------------

deploy_install_user() {
	user_create      $DEPLOY
	user_lock_pass   $DEPLOY
	user_remove_sudo $DEPLOY
}

deploy_uninstall_user() {
	user_remove $DEPLOY
}

deploy_rename_user() {
	user_rename $DEPLOY $DEPLOY1
}

# deploy run dir module ------------------------------------------------------

deploy_install_run_dir() {
	# make dir for app unix socket that www-data group (nginx process) can see.
	# this avoids giving nginx full access to the app dir (you might still want
	# to do that if you want nginx to also serve static public files).
	# setgid on the dir is important because the app itself can't change the
	# group of the socket file (it sets the mode to 0660, it's all it can do).
	save "d /run/$DEPLOY 02750 $DEPLOY www-data -" /etc/tmpfiles.d/$DEPLOY.conf
	systemd-tmpfiles --create /etc/tmpfiles.d/$DEPLOY.conf
}

deploy_uninstall_run_dir() {
	rm_dir /run/$DEPLOY
}

# deploy git module ----------------------------------------------------------

deploy_install_git() {
	git_keys_update $DEPLOY
	git_config_user "mm@allegory.ro" "Many Machines"
}

deploy_uninstall_git() {
	true
}
