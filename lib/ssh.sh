# ssh lib: ssh config and operation wrappers.

ssh_cmd_opt() { # MACHINE=
	R1=(ssh
-o ConnectTimeout=3
-o PreferredAuthentications=publickey
-o UserKnownHostsFile=var/machines/$MACHINE/ssh_hostkey
-o ControlMaster=auto
-o ControlPath=~/.ssh/control-%h-%p-%r
-o ControlPersist=600
-i var/machines/$MACHINE/ssh_key-mm-$HOSTNAME
)
	[ "$MM_SSH_TTY" ] && R1+=(-t) || R1+=(-o BatchMode=yes)
}

ssh_cmd() { # MACHINE= HOST=
	ssh_cmd_opt
	R1+=(root@$HOST)
}

quote_args() { # ARGS...
	# must use an array because we need to quote each arg individually,
	# and not concat and expand them to pass them along, becaue even
	# when quoted they may contain spaces and would expand incorrectly.
	R1=()
	for arg in "$@"; do
		R1+=("$(printf "%q" "$arg")")
	done
}

ssh_to() { # MACHINE|DEPLOY COMMAND ...
	ip_of "$1"; shift
	MACHINE=$R2 HOST=$R1 ssh_cmd; local cmd=("${R1[@]}")
	quote_args "$@"; local args=("${R1[@]}")
	run "${cmd[@]}" "${args[@]}" || die "ssh_to $MACHINE: [$?]"
}

ssh_bash() { # MACHINE|DEPLOY COMMAND ARGS ...
	ip_of "$1"; shift
	MACHINE=$R2 HOST=$R1 ssh_cmd; local cmd=("${R1[@]}")
	quote_args "$@"; local args=("${R1[@]}")
	must "${cmd[@]}" bash -c "\"${args[*]}\""
}

ssh_script() { # MACHINE|DEPLOY "SCRIPT"
	if [ "$MM_DEBUG_LIB" ]; then
		# rsync lib to machine and load from there:
		# slower (takes ~1s) but reports line numbers correctly on errors.
		QUIET=1 SRC_DIR=lib DST_DIR=.mm DST_MACHINE="$1" rsync_dir
		ssh_to "$1" bash -s <<< "
MACHINE=$MACHINE
VERBOSE=$VERBOSE
DEBUG=$DEBUG
. ~/.mm/lib/all
$2
"
	else
		# include lib contents in the script:
		# faster but doesn't report line numbers correctly on errors in lib code.
		ssh_to "$1" bash -s <<< "
MACHINE=$MACHINE
VERBOSE=$VERBOSE
DEBUG=$DEBUG
shopt -s nullglob
set -o pipefail
$(cat lib/*.sh)
$2
"
	fi
}

ssh_hostkey() {
	ip_of "$1"; local MACHINE="$R2"
	catfile var/machines/$MACHINE/ssh_hostkey
}

ssh_hostkey_update() {
	ip_of "$1"; local IP=$R1; local MACHINE=$R2
	say "Updating SSH host fingerprint for machine: $MACHINE ..."
	must ssh-keyscan -4 -T 2 -t rsa $IP > var/machines/$MACHINE/ssh_hostkey
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
  IdentityFile $HOME/.ssh/${KEYNAME}.id_rsa
  UserKnownHostsFile $HOME/.ssh/${KEYNAME}.hostkey "
	[ "$UNSTABLE_IP" ] && s+="
  CheckHostIP no"
	save "$s" $CONFIG
	must chown $USER:$USER -R $HOME/.ssh
	outdent
}

ssh_key_update_for_user() { # USER KEYNAME KEY HOSTKEY
	local USER="$1"
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	local KEYNAME="$2"
	local KEY="$3"
	local HOSTKEY="$4"
	checkvars USER KEYNAME KEY- HOSTKEY-
	say "Updating SSH key '$KEYNAME' for user '$USER'..."
	indent

	must mkdir -p $HOME/.ssh

	local KEYFILE=$HOME/.ssh/${KEYNAME}.id_rsa
	save "$KEY" $KEYFILE $USER

	local HOSTKEYFILE=$HOME/.ssh/${KEYNAME}.hostkey
	save "$HOSTKEY" $HOSTKEYFILE $USER

	must chown $USER:$USER -R $HOME/.ssh

	outdent
}

ssh_host_key_update_for_user() { # USER HOST KEYNAME KEY HOSTKEY [unstable_ip]
	ssh_key_update_for_user "$1" "$3" "$4" "$5"
	ssh_host_update_for_user "$1" "$2" "$3" "$6"
}

ssh_pubkey() { # USER KEYNAME
	local USER="$1"
	local KEYNAME="$2"
	checkvars USER KEYNAME
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	cat $HOME/.ssh/authorized_keys | grep " $KEYNAME\$"
}

ssh_pubkeys() { # FMT [USERS] [KEYNAME] [MM_PUBKEY]
	local FMT="$1"
	local USERS="$2"
	local KEYNAME="$3"
	local MM_PUBKEY="$4"
	checkvars FMT-
	[ "$USERS" ] || USERS=`echo root; ls -1 /home`
	for USER in $USERS; do
		local HOME=/home/$USER; [ $USER == root ] && HOME=/root
		local kf=$HOME/.ssh/authorized_keys
		[ -f $kf ] || continue
		local line
		while IFS= read -r line; do
			while read -r type key name; do
				[ "$key" ] || continue
				[ -z "$KEYNAME" -o "$name" == "$KEYNAME" ] || continue
				local match=; [ "$line" == "$MM_PUBKEY" ] && match=YES
				printf "$FMT" "$MACHINE" $USER "${key: -20}" $name $match
			done <<< "$line"
		done < $kf
	done
}

ssh_pubkey_update_for_user() { # USER KEYNAME PUBKEY|--remove
	local USER="$1"
	local KEYNAME="$2"
	local PUBKEY="$3"
	checkvars USER KEYNAME PUBKEY-
	say "Updating SSH public key '$KEYNAME' for user '$USER'..."
	indent
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	[ -d $HOME ] || die "No home dir for user '$USER'"
	local ak=$HOME/.ssh/authorized_keys
	[ -f $ak ] || {
		say "Creating file $ak..."
		must mkdir -p $HOME/.ssh
		must chmod 700 $HOME/.ssh
		must touch $ak
		must chmod 600 $ak
		must chown $USER:$USER -R $HOME/.ssh
	}
	local UP_PUBKEY="$(grep " $KEYNAME\$" $ak)"
	if [[ "$PUBKEY" == --remove && "$UP_PUBKEY" == "" ]]; then
		say "Key not found."
	elif [[ "$PUBKEY" == "$UP_PUBKEY" ]]; then
		say "Key is the same."
	else
		remove_line "$KEYNAME\$" $ak
		if [[ "$PUBKEY" != --remove ]]; then
			must append "$PUBKEY"$'\n' $ak
		fi
	fi
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

# SRC_DIR= [DST_DIR=] [LINK_DIR=] [SRC_MACHINE=] [DST_MACHINE=] [PROGRESS=1] [DRY] [VERBOSE] rsync_cmd
rsync_cmd() {
	[ "$DST_DIR" ] || DST_DIR="$SRC_DIR"
	checkvars SRC_DIR DST_DIR
	[ "$LINK_DIR" ] && {
		LINK_DIR="$(realpath "$LINK_DIR")" # --link-dest path must be absolute!
		checkvars LINK_DIR
	}

	[ "$SRC_MACHINE" ] && { ip_of "$SRC_MACHINE"; SRC_MACHINE=$R2; SRC_DIR="root@$R1:$SRC_DIR"; }
	[ "$DST_MACHINE" ] && { ip_of "$DST_MACHINE"; DST_MACHINE=$R2; DST_DIR="root@$R1:$DST_DIR"; }

	say "Sync'ing remote dir '${SRC_MACHINE:-local}' -> '${DST_MACHINE:-local}':"
	say "  src: $SRC_DIR"
	say "  dst: $DST_DIR"
	[ "$LINK_DIR" ] && say "  lnk: $LINK_DIR"
	[ "$DRY" ] && { say "  dry mode!"; local VERBOSE=1; }

	MACHINE=$DST_MACHINE ssh_cmd_opt; local ssh_cmd=("${R1[@]}")

	# NOTE: use `foo/bar/./baz/qux` dot syntax to end up with `$DST_DIR/baz/qux` !
	R1=(rsync ${DELETE:+--delete} --relative --timeout=5
		${PROGRESS:+--info=progress2}
		${LINK_DIR:+--link-dest="$LINK_DIR"}
		${DRY:+--dry-run}
		${VERBOSE:+-v}
		-e "${ssh_cmd[*]}"
		-aHR "$SRC_DIR" "$DST_DIR"
	)
}

rsync_dir() {
	rsync_cmd
	must "${R1[@]}"
}
