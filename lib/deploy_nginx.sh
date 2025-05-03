# deploy nginx config

deploy_nginx_config() { # DOMAIN= HTTP_UNIX_SOCKET=|HTTP_PORT=

	[[ "$HTTP_PORT$HTTP_UNIX_SOCKET" ]] || die "HTTP_PORT or HTTP_UNIX_SOCKET required"
	[[ $HTTP_PORT        ]] && checkvars HTTP_PORT
	[[ $HTTP_UNIX_SOCKET ]] && checkvars HTTP_UNIX_SOCKET

	checkvars DOMAIN ACME_THUMBPRINT

	local acme_location="\
	location ~ ^/\.well-known/acme-challenge/([-_a-zA-Z0-9]+)$ {
		default_type text/plain;
		return 200 \"\$1.$ACME_THUMBPRINT\";
	}
"

	local error_page="\
	error_page 502 503 504 /5xx.html;
	location /5xx.html {
		root /var/www/$DEPLOY/5xx.html;
	}
"

	local proxy_options="\
		${HTTP_PORT:+proxy_pass http://127.0.0.1:$HTTP_PORT;}
		${HTTP_UNIX_SOCKET:+proxy_pass http://unix:/run/$DEPLOY/http.sock;}
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

	local nginx_conf="\
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
	ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:!3DES:!RC4:!MD5:!ADH:!AECDH';
	ssl_prefer_server_ciphers on;
	ssl_session_cache shared:SSL:10m;
	ssl_session_timeout 4h;
	ssl_session_tickets on;
	ssl_certificate      /home/$DEPLOY/ssl_certificate;
	ssl_certificate_key  /home/$DEPLOY/ssl_certificate_key;
	ssl_dhparam          /etc/nginx/dhparam.pem;

	# HSTS with preloading to google. Another amazing tech from the web people.
	add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\" always;

	# NOTE: nginx nested locations don't inherit proxy options, so we copy-paste them!

$locations
$error_page
$acme_location
}
"

	save "$nginx_conf" /etc/nginx/sites-enabled/$DEPLOY
}

deploy_nginx_copy_5xx_html() {
	local src=/home/$DEPLOY/app/www/5xx.html
	local dst=/var/www/$DEPLOY/5xx.html
	if [[ -f $src ]]; then
		cp_file $src $dst
	else
		save "Server down!" $dst
	fi
}

deploy_nginx_ln_ssl_files() {
	acme_cert_keyfile; local KEY=$R1
	acme_cert_cerfile; local CER=$R1
	[[ -f $KEY && -f $CER ]] || {
		KEY=/etc/nginx/selfsigned.key
		CER=/etc/nginx/selfsigned.crt
	}
	ln_file $KEY /home/$DEPLOY/ssl_certificate_key;
	ln_file $CER /home/$DEPLOY/ssl_certificate;
}

deploy_preinstall_nginx() {
	[[ $DOMAIN ]] || return 0
	acme_cert_restore
}

deploy_install_nginx() {
	[[ $HTTP_PORT || $HTTP_UNIX_SOCKET ]] || return 0
	[[ $DOMAIN ]] || return 0

	deploy_nginx_copy_5xx_html
	deploy_nginx_ln_ssl_files
	deploy_nginx_config
	nginx_reload
	if [[ ! $NOSSL ]]; then
		acme_cert_issue
		deploy_nginx_ln_ssl_files
		nginx_reload
	fi
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
