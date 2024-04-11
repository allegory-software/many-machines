# deploy lib: programs for deployments admin, running as root on a machine administered by mm.

machine_deploys() {
	local USER
	for USER in `ls -1 /home`; do
		[ -L "/home/$USER/app" ] && echo $USER
	done
}

DI_FMT="%-10s %-10s %-10s %-10s %-10s %-10s\n"
DE_FMT="%-10s %-10s %s\n"
machine_deploy_info_header() {
	printf "$DI_FMT" "MACHINE" "DEPLOY" "STATUS" "APP" "APP_COM" "SDK_COM"
}
machine_deploy_info_line() {
	local DEPLOY=$1
	local APP="$(readlink /home/$DEPLOY/app)"
	local APP_COMMIT; APP_COMMIT="$(cd /home/$DEPLOY/app     && run_as $DEPLOY git rev-parse --short HEAD)" || return
	local SDK_COMMIT; SDK_COMMIT="$(cd /home/$DEPLOY/app/sdk && run_as $DEPLOY git rev-parse --short HEAD)" || return
	local STATUS; app running && STATUS="RUNNING" || STATUS="-"
	printf "$DI_FMT" "$MACHINE" "$DEPLOY" "$STATUS" "$APP" "$APP_COMMIT" "$SDK_COMMIT"
}
machine_deploy_info_line_fail() { # DEPLOY ERR
	printf "$DE_FMT" "$MACHINE" "$1" "$2"
}
machine_deploys_info() {
	local DEPLOY
	for DEPLOY in `machine_deploys`; do
		local s
		if s="$(machine_deploy_info_line $DEPLOY 2>&1)"; then
			printf "%s\n" "$s"
		else
			machine_deploy_info_line_fail $DEPLOY "$s"
		fi
	done
}

deploy_nginx_config() { # DOMAIN= HTTP_PORT= [ACME=1] $0

	# acme thumbprint got with `acme.sh --register-account` (thumbprint is public).
	local ACME_THUMBPRINT="yWTiBNPg2BAKLxC66JgGTYG8IEGPTFxIe0V3qA5Jfd0"

	local acme_location="\
	location ~ ^/\.well-known/acme-challenge/([-_a-zA-Z0-9]+)$ {
		default_type text/plain;
		return 200 \"\$1.$ACME_THUMBPRINT\";
	}
"

	local nginx_conf

	if [ "$ACME" ]; then

		checkvars DOMAIN

		nginx_conf="\
server {
	listen 80;
	server_name $DOMAIN;

$acme_location
}
"
	else

		checkvars HTTP_PORT DOMAIN

		local error_page="\
	error_page 502 503 504 /5xx.html;
	location /5xx.html {
		root /var/www/$DOMAIN;
	}
"

		local proxy_options="
		proxy_pass http://127.0.0.1:$HTTP_PORT;
		proxy_set_header X-Forwarded-Host \$http_host;
		proxy_set_header X-Forwarded-For  \$proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Port \$server_port;
"

		local proxy_nobuffer_options="
		proxy_buffering off;
		proxy_cache off;
"

		nginx_conf="\
server {
	listen 80;
	server_name $DOMAIN;

	location / {
		return 301 https://\$host\$request_uri;
	}

$error_page
$acme_location
}

server {
	listen 443 ssl;
	server_name $DOMAIN;

	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ciphers ECDH+AESGCM:ECDH+AES256:ECDH+AES128:DH+3DES:!ADH:!AECDH:!MD5;
	ssl_prefer_server_ciphers on;
	ssl_session_cache shared:SSL:10m;
	ssl_session_timeout 4h;
	ssl_session_tickets on;
	ssl_certificate      /root/.acme.sh.etc/$DOMAIN/fullchain.cer;
	ssl_certificate_key  /root/.acme.sh.etc/$DOMAIN/$DOMAIN.key;
	ssl_dhparam          /etc/nginx/dhparam.pem;

	# HSTS with preloading to google. Another amazing tech from the web people.
	add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\" always;

	# NOTE: nginx nested locations don't inherit proxy options, so we copy-paste them!

	location / {
		$proxy_options
	}

	location /xrowset.events {
		$proxy_options
		$proxy_nobuffer_options
	}

	location /api.txt {
		$proxy_options
		$proxy_nobuffer_options
	}

$error_page
$acme_location
}
"

fi

	save "$nginx_conf" /etc/nginx/sites-enabled/$DOMAIN
	say -n "Reloading nginx config... "
	must nginx -s reload
	say "OK"
}

deploy_nginx_config_acme() {
	ACME=1 deploy_nginx_config
}

deploy_nginx_config_remove() {
	local DOMAIN="$1"
	[ "$DOMAIN" ] || return 0
	rm_file /etc/nginx/sites-enabled/$DOMAIN
}

deploy_issue_cert() { # DOMAIN
	local DOMAIN="$1"
	checkvars DOMAIN

	say "Issuing SSL certificate for $DOMAIN with acme.sh ... "
	local keyfile=/root/.acme.sh.etc/$DOMAIN/$DOMAIN.key
	deploy_nginx_config_acme
	acme_sh --issue -d $DOMAIN --stateless
	[ -f $keyfile ] || die "SSL certificate was NOT created: $keyfile."
}

deploy_remove() { # DEPLOY DOMAIN=
	local DEPLOY="$1"
	checkvars DEPLOY

	user_remove $DEPLOY

	mysql_drop_db $DEPLOY
	mysql_drop_user localhost $DEPLOY

	[ "$DOMAIN" ] && deploy_nginx_config_remove

	say "Deploy removed."
}

app() {
	checkvars DEPLOY APP
	must pushd /home/$DEPLOY/$APP
	VARS="DEBUG VERBOSE" run_as $DEPLOY ./$APP "$@"
	popd
}

deploy_prepare() {
	checkvars DEPLOY MYSQL_PASS GIT_HOSTS-

	user_create    $DEPLOY
	user_lock_pass $DEPLOY

	#ssh_pubkey_update $KEYNAME $DEPLOY mm "$SSH_PUBKEY"
	#ssh_pubkey_for_user $DEPLOY mm  # print it so we can check it

	git_keys_update $DEPLOY
	git_config_user "mm@allegory.ro" "Many Machines"

	mysql_create_db     $DEPLOY
	mysql_create_user   localhost $DEPLOY "$MYSQL_PASS"
	mysql_grant_user_db localhost $DEPLOY $DEPLOY
	mysql_gen_my_cnf    localhost $DEPLOY "$MYSQL_PASS" $DEPLOY

	say "Deploy prepare done."
}

deploy() {

	[ -d /home/$DEPLOY ] || deploy_prepare

	checkvars DEPLOY REPO APP APP_VERSION SDK_VERSION
	say "Deploying APP=$APP ENV=$ENV VERSION=$APP_VERSION SDK_VERSION=$SDK_VERSION..."

	[ -d /home/$DEPLOY/$APP ] && app running && must app stop

	git_clone_for $DEPLOY $REPO /home/$DEPLOY/$APP "$APP_VERSION" app

	git_clone_for $DEPLOY \
		git@github.com:allegory-software/allegory-sdk \
		/home/$DEPLOY/$APP/sdk "$SDK_VERSION" sdk

	must cd /home/$DEPLOY/$APP/sdk
	run_as $DEPLOY git submodule update --init canvas-ui

	git_clone_for $DEPLOY \
		git@github.com:allegory-software/allegory-sdk-bin-debian10 \
		/home/$DEPLOY/$APP/sdk/bin/linux "$SDK_VERSION"

	deploy_gen_conf

	[[ $HTTP_PORT && $DOMAIN ]] && {
		local src=/home/$DEPLOY/$APP/www/5xx.html
		local dst=/var/www/$DOMAIN/5xx.html
		if [ -f "$src" ]; then
			cp_file $src $dst
		else
			save "Server down!" $dst
		fi
		deploy_nginx_config
	}

	must ln -sf $APP /home/$DEPLOY/app

	say; say "Installing the app..."
	must app install forealz

	say; must app start

	say; say "Deploy done."
}

deploy_secret_gen() {
	must openssl rand 46 | base64 # result is 64 chars
}

deploy_gen_conf() {
	checkvars MACHINE DEPLOY APP MYSQL_PASS SECRET
	local conf=/home/$DEPLOY/$APP/${APP}.conf
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

deploy_rename() { # OLD_DEPLOY NEW_DEPLOY [nosql]
	local OLD_DEPLOY="$1"
	local NEW_DEPLOY="$2"
	local OPT="$3"
	checkvars OLD_DEPLOY NEW_DEPLOY
	checkvars DEPLOY APP

	local MYSQL_PASS="$(mysql_pass $OLD_DEPLOY)"
	user_rename      $OLD_DEPLOY $NEW_DEPLOY
	mysql_rename_db  $OLD_DEPLOY $NEW_DEPLOY
	[ "$MYSQL_PASS" ] && \
		mysql_gen_my_cnf localhost $NEW_DEPLOY $MYSQL_PASS $NEW_DEPLOY

	deploy_gen_conf
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
