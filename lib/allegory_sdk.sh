# integration with Allegory-SDK-based apps

app() {
	checkvars DEPLOY
	must pushd /home/$DEPLOY/app
	VARS="DEBUG VERBOSE" must run_as $DEPLOY ./`readlink ../app` "$@"
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
	say; say "Starting the app..."
	must app start
	must app status
}

deploy_stop_app() {
	[[ -d /home/$DEPLOY/$APP ]] || return
	(app running && must app stop)
}

deploy_is_running_app() {
	[[ -d /home/$DEPLOY/$APP ]] || return
	(app running)
}

deploy_install_app() {

	checkvars DEPLOY REPO APP APP_VERSION

	say
	say "Deploying APP=$APP ENV=$ENV VERSION=$APP_VERSION ..."

	say
	git_clone_for $DEPLOY $REPO /home/$DEPLOY/$APP "$APP_VERSION" app

	must ln -sTf $APP /home/$DEPLOY/app

	say
	deploy_gen_conf

	say; say "Installing the app..."
	must app install forealz

}

deploy_uninstall_app() {
	deploy_stop app
	checkvars DEPLOY APP
	rm_dir /home/$DEPLOY/$APP
}
