ssh_cmd_opt() { # MACHINE=
	R1="ssh
-oBatchMode=yes
-oConnectTimeout=3
-oPreferredAuthentications=publickey
-oUserKnownHostsFile=var/machines/$MACHINE/ssh_hostkey
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
	local MACHINE="$1"; shift
	ssh_to "$MACHINE" bash -c "\"$@\""
}

ssh_hostkey() {
	ip_of "$1"; local MACHINE="$R2"
	local hkf=var/machines/$MACHINE/ssh_hostkey
	must catfile $hkf
}

ssh_hostkey_update() {
	ip_of "$1"; local MACHINE="$R2"
	say -n "Updating SSH host fingerprint for: $MACHINE ... "
	must ssh-keyscan -4 -T 2 -t rsa $R1 > var/machines/$MACHINE/ssh_hostkey
}

ssh_host_update_for_user() { # USER HOST KEYNAME [unstable_ip]
	local USER="$1"
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	local HOST="$2"
	local KEYNAME="$3"
	local UNSTABLE_IP="$4"
	checkvars USER HOST KEYNAME
	say "Assigning SSH key '$KEYNAME' to host '$HOST' for user '$USER' ..."; indent
	must mkdir -p $HOME/.ssh
	local CONFIG=$HOME/.ssh/config
	touch "$CONFIG"
	local s="$(sed 's/^Host/\n&/' $CONFIG | sed '/^Host '"$HOST"'$/,/^$/d;/^$/d')"
	s="$s
Host $HOST
  HostName $HOST
  IdentityFile $HOME/.ssh/${KEYNAME}.id_rsa"
	[ "$UNSTABLE_IP" ] && s="$s
  CheckHostIP no"
	save "$s" $CONFIG
	must chown $USER:$USER -R $HOME/.ssh
	outdent
}

ssh_key_update_for_user() { # USER KEYNAME KEY
	local USER="$1"
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	local KEYNAME="$2"
	local KEY="$3"
	checkvars USER KEYNAME KEY-
	say "Updating SSH key '$KEYNAME' for user '$USER' ..."; indent
	must mkdir -p $HOME/.ssh
	local KEYFILE=$HOME/.ssh/${KEYNAME}.id_rsa
	save "$KEY" $KEYFILE $USER
	must chown $USER:$USER -R $HOME/.ssh
	outdent
}

ssh_host_key_update_for_user() { # USER HOST KEYNAME KEY [unstable_ip]
	ssh_key_update_for_user "$1" "$3" "$4"
	ssh_host_update_for_user "$1" "$2" "$3" "$5"
}

ssh_pubkey_for_user() { # USER KEYNAME
	local USER="$1"
	local KEYNAME="$2"
	checkvars USER KEYNAME
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	cat $HOME/.ssh/authorized_keys | grep " $KEYNAME\$"
}

ssh_pubkey_update_for_user() { # USER KEYNAME PUBKEY
	local USER="$1"
	local KEYNAME="$2"
	local PUBKEY="$3"
	checkvars USER KEYNAME PUBKEY-
	say "Updating SSH public key '$KEYNAME' for user '$USER' ..."; indent
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	local ak=$HOME/.ssh/authorized_keys
	must mkdir -p $HOME/.ssh
	[ -f $ak ] && must sed -i "/ $KEYNAME/d" $ak
	local newline=$'\n'
	must append "$PUBKEY$newline" $ak
	must chmod 600 $ak
	must chown $USER:$USER -R $HOME/.ssh
	outdent
}

ssh_pubkey_update() { # KEYNAME PUBKEY [USERS]
	local KEYNAME="$1"
	local PUBKEY="$2"
	checkvars KEYNAME PUBKEY-
	local USERS="$3"
	[ "$USERS" ] || USERS="$(echo root; machine_deploys)"
	for USER in $USERS; do
		ssh_pubkey_update_for_user $USER $KEYNAME "$PUBKEY"
	done
}

ssh_git_keys_update_for_user() { # USER
	local USER="$1"
	checkvars USER GIT_HOSTS-
	say "Updating git keys for user: $USER ..."; indent
	for NAME in $GIT_HOSTS; do
		say "Updating key: $NAME ..."
		local -n HOST=${NAME^^}_HOST
		local -n SSH_KEY=${NAME^^}_SSH_KEY
		checkvars HOST SSH_KEY-
		ssh_host_key_update_for_user $USER $HOST mm_$NAME "$SSH_KEY" unstable_ip
	done
	outdent
}

ssh_git_keys_update() {
	local USER
	for USER in $(echo root; machine_deploys); do
		ssh_git_keys_update_for_user $USER
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

	say -n "Sync'ing dir
  src: $SRC_DIR
  dst: $DST_DIR "
	[ "$LINK_DIR" ] && say -n "
  lnk: $LINK_DIR "
	say -n "
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
