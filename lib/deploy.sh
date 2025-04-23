# deploy lib: programs for deployments admin, running as root on a machine administered by mm.

# deploy app module ----------------------------------------------------------

deploy_secret_gen() {
	must openssl rand 46 | base64 # result is 64 chars
}

try_app() {
	checkvars DEPLOY APP
	must pushd /home/$DEPLOY/app
	VARS="DEBUG VERBOSE" run_as $DEPLOY ./$APP "$@"; local ret=$?
	popd
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
deploy_version_sdk() { _deploy_version app/sdk; }
deploy_version_canvas_ui() { _deploy_version app/sdk/canvas-ui; }

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

deploy_is_running_app() {
	[[ -d /home/$DEPLOY/app ]] || return
	try_app running
}

deploy_start_app() {
	say "Starting the app..."
	must app start
	must app status
}

deploy_stop_app() {
	deploy_is_running_app && must app stop
}

get_APP_STATUS() {
	try_app running && \
		echo ${LIGHTGRAY}up$ENDCOLOR || \
		echo ${LIGHTRED}DOWN!$ENDCOLOR
}

deploy_install_app() {
	checkvars DEPLOY REPO APP APP_VERSION
	(deploy_stop_app)
	[[ $FAST ]] && SUBMODULES=sdk
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
	checkvars MACHINE DEPLOY APP MYSQL_PASS SECRET
	local conf=/home/$DEPLOY/app/${APP}.conf
	save "\
--deploy vars
deploy = '$DEPLOY'
machine = '$MACHINE'
${ENV:+env = '$ENV'}
${APP_VERSION:+version = '$APP_VERSION'}
db_name = '$DEPLOY'
db_user = '$DEPLOY'
db_pass = '$MYSQL_PASS'
secret = '$SECRET'

--custom vars
${HTTP_PORT:+http_port = $HTTP_PORT}
${HTTP_UNIX_SOCKET:+http_unix_socket = '/run/$DEPLOY/http.sock'}
${HTTP_UNIX_SOCKET:+http_unix_socket_perms = '0660'}
${HTTP_COMPRESS:+http_compress = $HTTP_COMPRESS}
${SMTP_HOST:+smtp_host = '$SMTP_HOST'}
${SMTP_HOST:+smtp_user = '$SMTP_USER'}
${SMTP_HOST:+smtp_pass = '$SMTP_PASS'}
${DOMAIN:+host = '$DOMAIN'}
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
	for USER in `ls -1 /home`; do
		[[ -d /home/$USER/app ]] && printf "%s\n" $USER
	done
}

get_DEPLOYS() {
	local s=`machine_deploys`
	printf "%s\n" "${s//$'\n'/ }"
}

# deploy user module ---------------------------------------------------------

deploy_install_user() {
	user_create    $DEPLOY
	user_lock_pass $DEPLOY
	# make dir for app unix socket that www-data group (nginx process) can see.
	# this avoids giving nginx full access to the app dir (you might still want
	# to do that if you want nginx to also serve static public files).
	must mkdir -p /run/$DEPLOY
	must chown $DEPLOY:www-data /run/$DEPLOY
	# setgid on the dir is important because the app itself can't change the
	# group of the socket file (it sets the mode to 0660, it's all it can do).
	must chmod 2750 /run/$DEPLOY
}

deploy_uninstall_user() {
	user_remove $DEPLOY
}

deploy_rename_user() {
	user_rename $DEPLOY $DEPLOY1
}

# deploy git module ----------------------------------------------------------

deploy_install_git() {
	git_keys_update $DEPLOY
	git_config_user "mm@allegory.ro" "Many Machines"
}

# deploy mysql module --------------------------------------------------------

deploy_preinstall_mysql() {
	checkvars DEPLOY
	mysql_pass_gen_once var/deploys/$DEPLOY/mysql_pass
}

deploy_install_mysql() {
	checkvars DEPLOY MYSQL_PASS-
	mysql_create_db     $DEPLOY
	mysql_create_user   localhost $DEPLOY "$MYSQL_PASS"
	mysql_grant_user_db localhost $DEPLOY $DEPLOY
	mysql_gen_my_cnf    localhost $DEPLOY "$MYSQL_PASS" $DEPLOY
}

deploy_uninstall_mysql() {
	mysql_drop_db $DEPLOY
	mysql_drop_user localhost $DEPLOY
}

deploy_rename_mysql() {
	checkvars MYSQL_PASS
	mysql_rename_db $DEPLOY $DEPLOY1
	mysql_gen_my_cnf localhost $DEPLOY1 "$MYSQL_PASS" $DEPLOY1
}
