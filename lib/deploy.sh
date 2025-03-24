# deploy lib: programs for deployments admin, running as root on a machine administered by mm.

# deploy info ----------------------------------------------------------------

# get it from github: slow.
get_APP_WANT() {
	checkvars REPO APP_VERSION
	local s=$(git ls-remote $REPO refs/heads/$APP_VERSION)
	echo ${s:0:7}
}

# get it locally: fast but wrong.
_get_APP_WANT() {
	must pushd /home/$DEPLOY/app
	run_as $DEPLOY git rev-parse --short $APP_VERSION
	popd
}

get_APP_DEPL() {
	must pushd /home/$DEPLOY/app
	run_as $DEPLOY git rev-parse --short HEAD
	popd
}

get_APP_LATEST() {
	[[ `get_APP_WANT` == `get_APP_DEPL` ]] && echo ${LIGHTGRAY}yes$ENDCOLOR || echo ${LIGHTRED}NO!$ENDCOLOR
}

get_SDK_DEPL() {
	must pushd /home/$DEPLOY/app/sdk
	run_as $DEPLOY git rev-parse --short HEAD
	popd
}

get_APP_STATUS() {
	try_app running && echo ${LIGHTGRAY}up$ENDCOLOR || echo ${LIGHTRED}DOWN!$ENDCOLOR
}

# deploy modules -------------------------------------------------------------

deploy_install_user() {
	user_create    $DEPLOY
	user_lock_pass $DEPLOY
}

deploy_uninstall_user() {
	user_remove $DEPLOY
}

deploy_rename_user() {
	user_rename $DEPLOY $DEPLOY1
}

deploy_install_git() {
	git_keys_update $DEPLOY
	git_config_user "mm@allegory.ro" "Many Machines"
}

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

# deploy admin ---------------------------------------------------------------

deploy_secret_gen() {
	must openssl rand 46 | base64 # result is 64 chars
}

test_task() {
	local n=0
	while true; do
		n=$((n+1))
		say "Testing $n (E)"
		echo "Testing $n (O)"
		sleep .5
	done
}
