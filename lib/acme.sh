# acme.sh install and running

acme_sh() {
	local cmd_args="/root/.acme.sh/acme.sh --config-home $PWD/var/.acme.sh.etc"
	run $cmd_args "$@"
	local ret=$?; [ $ret == 2 ] && ret=0 # skipping gets exit code 2.
	[ $ret == 0 ] || die "$cmd_args $@ [$ret]"
}

acme_check() {
	say "Checking SSL certificate with acme.sh ... "
	acme_sh --cron
}

acme_install() {
	say "Installing acme.sh..."

	# install acme.sh to auto-renew SSL certs.
	must curl -sL https://get.acme.sh | must sh -s email=my@example.com --nocron --config-home $PWD/var/.acme.sh.etc 2>/dev/null

	# ZeroSSL is the default but it's very slow, so we're switching back to LE.
	acme_sh --set-default-ca --server letsencrypt

	say "acme.sh install done."
}

acme_ca_upload() {
	say "Uploading acme.sh CA files..."
	check_machine "$1"
	DELETE=1 SRC_DIR=/opt/mm/var/.acme.sh.etc/ca DST_DIR=/ DST_MACHINE=$1 rsync_dir
}
