# midnight commander config

mc_conf_upload() {
	check_machine "$1"
	say "Uploading mc config files to machine '$1' ..."
	cp_dir ~/.config/mc etc/home/.config/
	SRC_DIR=etc/home/./.config/mc DST_DIR=/root DST_MACHINE=$1 rsync_dir
	MACHINE=$1 ssh_script "mc_conf_spread"
}

mc_conf_spread() {
	local USER
	for USER in `ls -1 /home`; do
		say "Copying mc config files to user '$USER' ..."
		cp_dir /root/.config/mc /home/$USER/.config/ $USER
	done
}

