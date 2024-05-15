# midnight commander config

mc_conf_upload() { # MACHINE=
	say; say "Uploading mc config files to machine '$MACHINE' ..."
	#cp_dir ~/.config/mc etc/home/.config/
	SRC_DIR=etc/home/./.config/mc DST_DIR=/root DST_MACHINE=$MACHINE rsync_dir
	ssh_script "mc_conf_spread"
}

postinstall_mc() { mc_conf_upload; }

mc_conf_spread() {
	local USER
	for USER in `ls -1 /home`; do
		cp_dir /root/.config/mc /home/$USER/.config/ $USER
	done
}
