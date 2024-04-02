ssh_cmd_opt() { # MACHINE=
	R1="ssh
-o ConnectTimeout=3
-o PreferredAuthentications=publickey
-o UserKnownHostsFile=var/machines/$MACHINE/ssh_hostkey
-o ControlMaster=auto
-o ControlPath=~/.ssh/control-%h-%p-%r
-o ControlPersist=10
-i var/machines/$MACHINE/mm_ssh_key
"
	[ "$MM_SSH_TTY" ] && R1+=" -t" || R1+=" -o BatchMode=yes"
}

ssh_cmd() { # MACHINE= HOST=
	ssh_cmd_opt
	R1="$R1 root@$HOST"
}

quote_args() { # OUT_VARNAME ARGS...
	# must use an array because we need to quote each arg individually,
	# and not concat and expand them to pass them along, becaue even
	# when quoted they may contain spaces and would expand incorrectly.
	local -n _out=$1; shift
	for arg in "$@"; do
		_out+=("$(printf "%q" "$arg")")
	done
}

ssh_to() { # MACHINE|DEPLOY COMMAND ...
	ip_of "$1"; shift
	MACHINE=$R2 HOST=$R1 ssh_cmd
	local qargs; quote_args qargs "$@"
	must $R1 "${qargs[@]}"
}

ssh_bash() { # MACHINE|DEPLOY COMMAND ARGS ...
	ip_of "$1"; shift
	MACHINE=$R2 HOST=$R1 ssh_cmd
	local qargs; quote_args qargs "$@"
	must $R1 bash -c "\"${qargs[*]}\""
}

ssh_script() { # MACHINE|DEPLOY "SCRIPT"
	ssh_to "$1" bash -c "
shopt -s nullglob
set -o pipefail
$(machine_vars "$1")
$(cat lib/*.sh)
$2"
}

ssh_hostkey() {
	ip_of "$1"; local MACHINE="$R2"
	local hkf=var/machines/$MACHINE/ssh_hostkey
	must catfile $hkf
}

ssh_hostkey_update() {
	ip_of "$1"; local MACHINE="$R2"
	say -n "Updating SSH host fingerprint for machine: $MACHINE... "
	must ssh-keyscan -4 -T 2 -t rsa $R1 > var/machines/$MACHINE/ssh_hostkey
}

ssh_host_update_for_user() { # USER HOST KEYNAME [unstable_ip]
	local USER="$1"
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	local HOST="$2"
	local KEYNAME="$3"
	local UNSTABLE_IP="$4"
	checkvars USER HOST KEYNAME
	say "Assigning SSH key '$KEYNAME' to host '$HOST' for user '$USER'..."; indent
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
	say "Updating SSH key '$KEYNAME' for user '$USER'..."; indent
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
	say "Updating SSH public key '$KEYNAME' for user '$USER'..."; indent
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	[ -d $HOME ] || die "No home dir for user '$USER'"
	local ak=$HOME/.ssh/authorized_keys
	[ "$(cat $ak | grep " $KEYNAME\$")" != "$PUBKEY" ]; local ret=$?
	[ $ret == 0 ] && {
		must mkdir -p $HOME/.ssh
		[ -f $ak ] && must sed -i "/ $KEYNAME\$/d" $ak
		must append "$PUBKEY"$'\n' $ak
		must chmod 600 $ak
		must chown $USER:$USER -R $HOME/.ssh
	}
	say "Key is the same."
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
	say "Updating git keys for user '$USER'..."; indent
	for NAME in $GIT_HOSTS; do
		say "Updating git key: $NAME..."
		local -n HOST=${NAME^^}_HOST
		local -n SSH_KEY=${NAME^^}_SSH_KEY
		checkvars HOST SSH_KEY-
		ssh_host_key_update_for_user $USER $HOST mm_$NAME "$SSH_KEY" unstable_ip
	done
	outdent
}

ssh_git_keys_update() { # [USERS]
	local USERS="$1"
	[ "$USERS" ] || USERS="$(echo root; machine_deploys)"
	for USER in $USERS; do
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

	say "Sync'ing dir"
	say "  src: $SRC_DIR"
  	say "  dst: $DST_DIR"
	[ "$LINK_DIR" ] && say "  lnk: $LINK_DIR"
	say -n " ... "
	indent

	MACHINE=$DST_MACHINE ssh_cmd_opt
	local SSH_CMD_OPT="$R1"

	# NOTE: use `foo/bar/./baz/qux` dot syntax to end up with `$DST_DIR/baz/qux` !
	[ "$DRY" ] || must rsync --delete --timeout=5 \
		${PROGRESS:+--info=progress2} \
		${LINK_DIR:+--link-dest=$LINK_DIR} \
		-e "${SSH_CMD_OPT//$'\n'/ }" \
		-aHR "$SRC_DIR" "$DST_DIR"

	say "OK"
	outdent
}
