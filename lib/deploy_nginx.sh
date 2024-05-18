# deploy nginx config

deploy_nginx_config() { # DOMAIN= HTTP_UNIX_SOCKET=|HTTP_PORT= [ACME=1] [NOSSL=1] $0

	checkvars ACME_THUMBPRINT

	local acme_location="\
	location ~ ^/\.well-known/acme-challenge/([-_a-zA-Z0-9]+)$ {
		default_type text/plain;
		return 200 \"\$1.$ACME_THUMBPRINT\";
	}
"

	local nginx_conf

	if [[ $ACME ]]; then

		checkvars DOMAIN

		nginx_conf="\
server {
	listen 80;
	server_name $DOMAIN;

$acme_location
}
"
	else

		[[ "$HTTP_PORT$HTTP_UNIX_SOCKET" ]] || die "HTTP_PORT or HTTP_UNIX_SOCKET required"
		[[ $HTTP_PORT        ]] && checkvars HTTP_PORT
		[[ $HTTP_UNIX_SOCKET ]] && checkvars HTTP_UNIX_SOCKET

		checkvars DOMAIN

		local error_page="\
	error_page 502 503 504 /5xx.html;
	location /5xx.html {
		root /var/www/$DEPLOY/5xx.html;
	}
"

		local proxy_options="\
		${HTTP_PORT:+proxy_pass http://127.0.0.1:$HTTP_PORT;}
		${HTTP_UNIX_SOCKET:+proxy_pass http://unix:$HTTP_UNIX_SOCKET;}
		proxy_set_header X-Forwarded-Host \$http_host;
		proxy_set_header X-Forwarded-For  \$proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Port \$server_port;
"

		local proxy_nobuffer_options="\
		proxy_buffering off;
		proxy_cache off;
"

		local locations="\
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
"

		if [[ $NOSSL ]]; then

			nginx_conf="\
server {
	listen 80;
	server_name $DOMAIN;

$locations
$error_page
$acme_location
}
"
		else

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
	ssl_certificate      $ACME_DIR/${DOMAIN}_ecc/fullchain.cer;
	ssl_certificate_key  $ACME_DIR/${DOMAIN}_ecc/$DOMAIN.key;
	ssl_dhparam          /etc/nginx/dhparam.pem;

	# HSTS with preloading to google. Another amazing tech from the web people.
	add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\" always;

	# NOTE: nginx nested locations don't inherit proxy options, so we copy-paste them!

$locations
$error_page
$acme_location
}
"
		fi # NOSSL

	fi # ACME

	save "$nginx_conf" /etc/nginx/sites-enabled/$DEPLOY
	sayn "Reloading nginx config... "
	must nginx -s reload
	say "OK"
}

deploy_nginx_config_acme() {
	ACME=1 deploy_nginx_config
}

deploy_preinstall_nginx() {
	if md_var DOMAIN; then
		local DOMAIN=$R1
		md_var NOSSL || acme_cert_upload $MACHINE $DOMAIN
	fi
}

deploy_install_nginx() {
	[[ $HTTP_PORT || $HTTP_UNIX_SOCKET ]] || return 0
	local src=/home/$DEPLOY/app/www/5xx.html
	local dst=/var/www/$DEPLOY/5xx.html
	if [[ -f $src ]]; then
		cp_file $src $dst
	else
		save "Server down!" $dst
	fi
	local ACME; [[ ! $NOSSL && $DOMAIN && ! -f $ACME_DIR/${DOMAIN}_ecc/$DOMAIN.cer ]] && ACME=1
	deploy_nginx_config
}

deploy_uninstall_nginx() {
	rm_file /etc/nginx/sites-enabled/$DEPLOY
	rm_dir /var/www/$DEPLOY
}

deploy_rename_nginx() {
	local DIR=/etc/nginx/sites-enabled
	mv_file $DIR/$DEPLOY $DIR/$DEPLOY1
	local DIR=/var/www
	mv_dir $DIR/$DEPLOY $DIR/$DEPLOY1
}
