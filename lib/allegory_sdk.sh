# integration with Allegory-SDK-based apps

app() {
	checkvars DEPLOY APP
	must pushd /home/$DEPLOY/app
	VARS="DEBUG VERBOSE" must run_as $DEPLOY ./$APP "$@"
	popd
}

deploy_version_app() {
	must pushd /home/$DEPLOY/app
	run_as $DEPLOY git rev-parse --short HEAD
	popd
}

deploy_version_sdk() {
	must pushd /home/$DEPLOY/app/sdk
	run_as $DEPLOY git rev-parse --short HEAD
	popd
}

deploy_start_app() {
	say "Starting the app..."
	must app start
	must app status
}

deploy_stop_app() {
	[[ -d /home/$DEPLOY/app ]] || return
	(app running && must app stop)
}

deploy_is_running_app() {
	[[ -d /home/$DEPLOY/app ]] || return
	(app running)
}

deploy_install_app() {
	checkvars DEPLOY REPO APP APP_VERSION
	deploy_stop_app
	[[ $FAST ]] && SUBMODULES=
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

