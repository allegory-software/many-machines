# integration with Allegory-SDK-based apps

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
