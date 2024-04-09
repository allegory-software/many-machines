
machine_vars() {
	machine_of "$1"; local MACHINE=$R1
	read_vars var/machines/$MACHINE

	mysql_root_pass "$MACHINE"; local MYSQL_ROOT_PASS="$R1"
	catfile var/dhparam.pem                   ; local DHPARAM="$R1"
	catfile var/mm_ssh_key.pub                ; local MM_SSH_PUBKEY="$R1"
	git_vars                                  ; VARS+=$'\n'"$R1"

	# custom vars
	catfile var/machine_vars                ""; VARS+=$'\n'"$R1"
	catfile var/machines/$MACHINE/var_files ""; local VAR_FILES="$R1"
	local FILE; for FILE in $VAR_FILES; do
		catfile var/$FILE; VARS+=$'\n'"$R1"
	done
	catfile var/machines/$MACHINE/vars      ""; VARS+=$'\n'"$R1"

	R1="$VARS
MACHINE=$MACHINE
MM_SSH_PUBKEY=\"$MM_SSH_PUBKEY\"
DHPARAM=\"$DHPARAM\"
MYSQL_ROOT_PASS=\"$MYSQL_ROOT_PASS\"
"
}

machine_vars_upload() {
	MACHINE="$1"; checkvars MACHINE
	machine_vars "$MACHINE"; local VARS="$R1"
	say "Uploading env vars to $MACHINE in /root/.mm/vars ..."; indent
	echo "$VARS" | ssh_to "$MACHINE" bash -c "mkdir -p /root/.mm; cat > /root/.mm/vars"
	outdent
}


rsync_machine() { # MD
	machine_of "$1"; local MACHINE=$R1
	#var/fix-links
	SRC_DIR="$(realpath var)" DST_DIR="$(realpath var1)" DST_MACHINE="$MACHINE" rsync_cmd
	must "${R1[@]}" \
		--exclude-from=var/.private \
		--include-from=<(machine_var_files $MACHINE) \
		--copy-unsafe-links
}
