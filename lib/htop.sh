# htop config

htop_conf_upload() { # MACHINE=
	say; say "Uploading htop config files to machine '$MACHINE' ..."
	NODELETE=1 SRC_DIR=etc/home/./.config/htop DST_DIR=/root DST_MACHINE=$MACHINE rsync_dir
	ssh_script "htop_conf_spread"
}

postinstall_htop() { htop_conf_upload; }

htop_conf_spread() {
	local USER
	for USER in `ls -1 /home`; do
		cp_dir /root/.config/htop /home/$USER/.config/ $USER
	done
}
