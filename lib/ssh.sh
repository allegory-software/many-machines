ssh_cmd_opt() { # MACHINE=
	R1="ssh
-oBatchMode=yes
-oConnectTimeout=3
-oPreferredAuthentications=publickey
-oUserKnownHostsFile=var/ssh_host_keys
-oControlMaster=auto
-oControlPath=~/.ssh/control-%h-%p-%r
-oControlPersist=10
-ivar/machines/$MACHINE/ssh_key
"
}

ssh_cmd() { # MACHINE= HOST=
	ssh_cmd_opt
	R1="$R1
root@$HOST"
}

ssh_to() { # MACHINE|DEPLOY COMMAND ...
	ip_of "$1"; shift
	MACHINE=$R2 HOST=$R1 ssh_cmd
	must $R1 "$@" # NOTE: arg expansion only on newlines (but not spaces) due to IFS
}

ssh_bash() { # MACHINE COMMANDS ...
	MACHINE="$1"; shift
	ssh_to "$MACHINE" bash -c "\"$@\""
}

ssh_hostkey_update() { # HOST HOSTKEY
	local host="$1"
	local fp="$2"
	checkvars host fp-
	say "Updating SSH host fingerprint for host $host (/etc/ssh) ..."; indent
	local kh=/etc/ssh/ssh_known_hosts
	local s="$(run ssh-keygen -R "$host" -f $kh 2>&1 | indent-stdin)" # remove host line if found
	echo -n "$s" 1>&2
	local newline=$'\n'
	append "$fp$newline" $kh
	must chmod 644 $kh
	outdent
}

ssh_host_update() { # HOST KEYNAME [unstable_ip]
	local host="$1"
	local keyname="$2"
	checkvars host keyname
	say "Assigning SSH key '$keyname' to host '$host' $HOME $3 ..."; indent
	must mkdir -p $HOME/.ssh
	local CONFIG=$HOME/.ssh/config
	touch "$CONFIG"
	local s="$(sed 's/^Host/\n&/' $CONFIG | sed '/^Host '"$1"'$/,/^$/d;/^$/d')"
	s="$s
Host $1
  HostName $1
  IdentityFile $HOME/.ssh/${2}.id_rsa"
	[ "$3" ] && s="$s
  CheckHostIP no"
	save "$s" $CONFIG
	must chown $USER:$USER -R $HOME/.ssh
	outdent
}

ssh_key_update() { # keyname key
	say "Updating SSH key '$1' ($HOME) ..."; indent
	must mkdir -p $HOME/.ssh
	local idf=$HOME/.ssh/${1}.id_rsa
	save "$2" $idf $USER
	must chown $USER:$USER -R $HOME/.ssh
	outdent
}

ssh_host_key_update() { # [HOME=] [USER=] HOST KEYNAME KEY [unstable_ip]
	ssh_key_update "$2" "$3"
	ssh_host_update "$1" "$2" "$4"
}

ssh_pubkey_for_user() { # [USER=] USER KEYNAME
	local USER="$1"
	local KEYNAME="$2"
	checkvars USER KEYNAME
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	cat $HOME/.ssh/authorized_keys | grep " $KEYNAME\$"
}

ssh_pubkey_update_for_user() { # USER KEYNAME KEY
	local USER="$1"
	local KEYNAME="$2"
	local KEY="$3"
	checkvars USER KEYNAME KEY-
	say "Updating SSH public key '$KEYNAME' for user '$USER' ..."; indent
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	local ak=$HOME/.ssh/authorized_keys
	must mkdir -p $HOME/.ssh
	[ -f $ak ] && must sed -i "/ $KEYNAME/d" $ak
	local newline=$'\n'
	must append "$KEY$newline" $ak
	must chmod 600 $ak
	must chown $USER:$USER -R $HOME/.ssh
	outdent
}

ssh_pubkey_update() { # KEYNAME KEY
	local KEYNAME="$1"
	local KEY="$2"
	checkvars KEYNAME KEY-
	(
	cd /home || exit 1
	shopt -s nullglob
	for USER in *; do
		ssh_pubkey_update_for_user $USER $KEYNAME "$KEY"
	done
	ssh_pubkey_update_for_user root $KEYNAME "$KEY"
	)
}

ssh_git_keys_update_for_user() { # USER
	local USER="$1"
	checkvars USER GIT_HOSTS-
	for NAME in $GIT_HOSTS; do
		local -n HOST=${NAME^^}_HOST
		local -n SSH_KEY=${NAME^^}_SSH_KEY
		checkvars HOST SSH_KEY-

		HOME=/home/$USER USER=$USER ssh_host_key_update \
			$HOST mm_$NAME "$SSH_KEY" unstable_ip
	done
}

ssh_git_keys_update() {
	checkvars GIT_HOSTS-
	for NAME in $GIT_HOSTS; do
		say "Updating git keys for: $NAME"; indent
		local -n HOST=${NAME^^}_HOST
		local -n SSH_HOSTKEY=${NAME^^}_SSH_HOSTKEY
		local -n SSH_KEY=${NAME^^}_SSH_KEY
		checkvars HOST SSH_HOSTKEY- SSH_KEY-

		ssh_hostkey_update $HOST "$SSH_HOSTKEY"
		ssh_host_key_update $HOST mm_$NAME "$SSH_KEY" unstable_ip

		must pushd /home
		for USER in *; do
			[ -d /home/$USER/.ssh ] && \
				HOME=/home/$USER USER=$USER ssh_host_key_update \
					$HOST mm_$NAME "$SSH_KEY" unstable_ip
		done
		popd
		outdent
	done
}

# SRC_DIR= [DST_DIR=] [LINK_DIR=] [SRC_MACHINE=] [DST_MACHINE=] [PROGRESS=1] rsync_dir
rsync_dir() {
	[ "$DST_DIR" ] || DST_DIR="$SRC_DIR"
	checkvars SRC_DIR DST_DIR
	[ "$LINK_DIR" ] && {
		LINK_DIR="$(realpath "$LINK_DIR")" # --link-dest path must be absolute!
		checkvars LINK_DIR
	}

	[ "$SRC_MACHINE" ] && { ip_of "$SRC_MACHINE"; SRC_MACHINE=$R2; SRC_DIR="root@$R1:$SRC_DIR"; }
	[ "$DST_MACHINE" ] && { ip_of "$DST_MACHINE"; DST_MACHINE=$R2; DST_DIR="root@$R1:$DST_DIR"; }

	say-n "Sync'ing dir
  src: $SRC_DIR
  dst: $DST_DIR "
	[ "$LINK_DIR" ] && say-n "
  lnk: $LINK_DIR "
	say-n "
  ... "
	indent

	MACHINE=$DST_MACHINE ssh_cmd_opt
	local SSH_CMD_OPT="$R1"

	# NOTE: the dot syntax cuts out the path before it as a way to make the path relative.
	[ "$DRY" ] || must rsync --delete --timeout=5 \
		${PROGRESS:+--info=progress2} \
		${LINK_DIR:+--link-dest=$LINK_DIR} \
		-e "${SSH_CMD_OPT//$'\n'/ }" \
		-aHR "$SRC_DIR/./." "$DST_DIR"

	rm -f $p $h
	say "OK"
	outdent
}
