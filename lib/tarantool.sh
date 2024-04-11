# tarantool install, admin and querying (not yet used)

tarantool_install() { # tarantool 2.10
	say "Instlaling Tarantool..."
	is_running tarantool && { say "Tarantool is running. Stop it first."; return 0; }
	must curl -L https://tarantool.io/BsbZsuW/release/2/installer.sh | bash
	apt_get_install tarantool
	say "Tarantool install done."
}

