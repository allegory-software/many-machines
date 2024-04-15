# deploy nginx config

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

