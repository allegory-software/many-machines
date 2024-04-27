
version_nginx() {
	nginx -v 2>&1 | awk '{print $3}'
}
