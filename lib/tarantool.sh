# tarantool install, admin and querying (not yet used)

install_tarantool() { # tarantool 3.0
	say "Instlaling Tarantool..."
	is_running tarantool && { say "Tarantool is running. Stop it first."; return 0; }
	must curl -L https://tarantool.io/oBlHHAA/release/3/installer.sh | bash
	apt_get_install tarantool
	# remove it or it breaks apt-get. this means no updates, just fresh installs every time.
	rm_dir /etc/apt/sources.list.d/tarantool_3.list
	say "Tarantool install done."
}
