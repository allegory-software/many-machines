# acme.sh install and running

ACME_DIR=/opt/mm/var/.acme.sh.etc
ACME_EMAIL=cosmin.apreutesei@gmail.com

preinstall_acme() {
	acme_ca_upload
}

install_acme() {
	say "Installing acme.sh..."

	# install acme.sh to auto-renew SSL certs.
	must curl -sSL https://get.acme.sh | must sh \
		-s email=$ACME_EMAIL \
		--nocron \
		--config-home $ACME_DIR

	# ZeroSSL is the default but it's very slow, so we're switching back to LE.
	acme_sh --set-default-ca --server letsencrypt

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

acme_ca_upload() {
	checkvars MACHINE
	say "Uploading acme.sh CA files to '$MACHINE' ..."
	DELETE=1 SRC_DIR=$ACME_DIR/ca           DST_DIR=/ DST_MACHINE=$MACHINE rsync_dir
	DELETE=1 SRC_DIR=$ACME_DIR/account.conf DST_DIR=/ DST_MACHINE=$MACHINE rsync_dir
}

acme_cert_upload() {
	checkvars MACHINE DOMAIN
	check_machine $MACHINE
	say "Uploading SSL cert files for domain '$DOMAIN' to '$MACHINE' ..."
	local DIR=$ACME_DIR/${DOMAIN}_ecc
	[[ -f $DIR/$DOMAIN.cer ]] || { say "Cert file not found: '$DIR/$DOMAIN.cer'"; return 1; }
	[[ -f $DIR/$DOMAIN.key ]] || { say "Cert file not found: '$DIR/$DOMAIN.key'"; return 1; }
	DELETE=1 SRC_DIR=$DIR DST_DIR=/ DST_MACHINE=$MACHINE rsync_dir
}

acme_cert_download() {
	local MACHINE=$1 DOMAIN=$2
	check_machine "$MACHINE"
	checkvars DOMAIN
	say "Uploading SSL cert files for domain '$DOMAIN' to '$MACHINE' ..."
	local DIR=$ACME_DIR/${DOMAIN}_ecc
	[[ -f $DIR/$DOMAIN.cer ]] || { say "Cert file not found: '$DIR/$DOMAIN.cer'"; return 1; }
	[[ -f $DIR/$DOMAIN.key ]] || { say "Cert file not found: '$DIR/$DOMAIN.key'"; return 1; }
	DELETE=1 SRC_DIR=$DIR DST_DIR=/ DST_MACHINE=$MACHINE rsync_dir
}

acme_issue_cert() { # DOMAIN
	local DOMAIN="$1"
	checkvars DOMAIN

	say "Issuing SSL certificate for $DOMAIN with acme.sh ... "
	local keyfile=$ACME_DIR/${DOMAIN}_ecc/$DOMAIN.key
	deploy_nginx_config_acme
	acme_sh --issue -d $DOMAIN --stateless --force
	[[ -f $keyfile ]] || die "SSL certificate was NOT created: $keyfile."
	deploy_nginx_config
}
