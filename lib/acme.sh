# acme.sh install and running

ACME_DIR=/root/.acme.sh.etc
ACME_EMAIL=cosmin.apreutesei@gmail.com

preinstall_acme() {
	acme_ca_upload
}

install_acme() {
	say "Installing acme.sh ..."

	# install acme.sh to auto-renew SSL certs.
	must curl -sSL https://get.acme.sh | must sh \
		-s email=$ACME_EMAIL \
		--nocron \
		--config-home $ACME_DIR

	# ZeroSSL is the default but it's very slow, so we're switching back to LE.
	acme_sh --set-default-ca --server letsencrypt

	save "\
/root/.acme.sh/acme.sh --cron --home /root/.acme.sh --config-home $ACME_DIR >/dev/null
nginx -s reload
" /etc/cron.daily/acme root 755

	say "acme.sh install done."
}

version_acme() {
	/root/.acme.sh/acme.sh -v | tail -1
}

acme_sh() {
	local cmd_args="/root/.acme.sh/acme.sh --config-home $ACME_DIR"
	run $cmd_args "$@"
	local ret=$?; [[ $ret == 2 ]] && ret=0 # skipping gets exit code 2.
	[[ $ret == 0 ]] || die "$cmd_args $@ [$ret]"
}

acme_cert_keyfile() { R1=$ACME_DIR/${DOMAIN}_ecc/$DOMAIN.key; }
acme_cert_cerfile() { R1=$ACME_DIR/${DOMAIN}_ecc/fullchain.cer; }

acme_ca_upload() {
	checkvars MACHINE
	SRC_DIR=/root/mm/var/./.acme.sh.etc/ca            DST_DIR=/root DST_MACHINE=$MACHINE rsync_dir
	SRC_DIR=/root/mm/var/./.acme.sh.etc/account.conf  DST_DIR=/root DST_MACHINE=$MACHINE rsync_dir
}

acme_cert_issue() { # DOMAIN=
	checkvars DOMAIN
	say "Issuing SSL certificate for domain: '$DOMAIN' ... "
	acme_sh --issue -d $DOMAIN --stateless "$@"
	nginx_reload
}

acme_cert_renew() { # DOMAIN=
	checkvars DOMAIN
	say "Renewing SSL certificate for domain: '$DOMAIN' ... "
	acme_sh --renew -d $DOMAIN "$@"
	nginx_reload
}

acme_cert_backup() {
	checkvars DEPLOY DOMAIN
	check_machine $MACHINE
	local d=.acme.sh.etc/${DOMAIN}_ecc
	if [[ ! -d /root/$d ]]; then
		say "No SSL certificate to back up for domain: '$DOMAIN'."
		return 1
	fi
	SRC_DIR=/root/./$d DST_DIR=/root/mm/var SRC_MACHINE=$MACHINE rsync_dir
}

acme_cert_restore() {
	must md_var DOMAIN; local DOMAIN=$R1
	checkvars MACHINE DOMAIN
	check_machine $MACHINE
	local d=.acme.sh.etc/${DOMAIN}_ecc
	[[ $(ssh_script "[[ -d /root/$d ]] && echo yes || true") == yes ]] && {
		say "Not uploading SSL certificate: dir '/root/$d' already present."
		return 1
	}
	SRC_DIR=/root/mm/var/./$d DST_DIR=/root DST_MACHINE=$MACHINE rsync_dir
}
