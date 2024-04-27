
install_nginx() {
	package_install nginx
	say "Configuring nginx..."
	# add dhparam.pem from mm (dhparam is public).
	save "$DHPARAM" /etc/nginx/dhparam.pem
	# remove nginx placeholder vhost.
	rm_file /etc/nginx/sites-enabled/default
	service_is_running nginx && nginx -s reload
}

version_nginx() {
	nginx -v 2>&1 | awk '{print $3}'
}
