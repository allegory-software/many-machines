# ssh lib: ssh config and operation wrappers.

ssh_cmd_opt() { # MACHINE= [KEYFILE=]
	checkvars MACHINE
	R1=(ssh
-o ConnectTimeout=3
-o PreferredAuthentications=publickey
-o UserKnownHostsFile=var/machines/$MACHINE/.ssh_hostkey
-o ControlMaster=auto
-o ControlPath=~/.ssh/control-%h-%p-%r
-o ControlPersist=600
-i ${SSH_KEYFILE:-var/machines/$MACHINE/.ssh_key}
)
	[[ $MM_SSH_TTY ]] && R1+=(-t) || R1+=(-o BatchMode=yes)
}

ssh_cmd() { # MACHINE= HOST=
	ip_of "$MACHINE"; local HOST=$R1
	ssh_cmd_opt
	R1+=(root@$HOST)
}

ssh_to() { # [AS_USER=] [AS_DEPLOY=1] MACHINE= COMMAND ARGS...
	[[ $AS_DEPLOY && $DEPLOY ]] && local AS_USER=$DEPLOY
	[[ $1 ]] || local MM_SSH_TTY=1
	ssh_cmd; local cmd=("${R1[@]}")
	quote_args "$@"; local args=("${R1[@]}")
	local sudo; [[ $AS_USER ]] && { [[ $1 ]] && sudo="sudo -i -u $AS_USER" || sudo="su - $AS_USER"; }
	run "${cmd[@]}" $sudo "${args[@]}" || die "MACHINE=$MACHINE ssh_to: [$?]"
}

ssh_script() { # [AS_USER=] [AS_DEPLOY=1] [MM_LIBS="lib1 ..."] MACHINE= [FUNCS="fn1 ..."] [VARS="VAR1 ..."] "SCRIPT" ARGS...
	local SCRIPT=$1; shift
	checkvars MACHINE SCRIPT-
	quote_args "$@"; local ARGS="${R1[*]}"
	[[ $FUNCS ]] && local FUNCS=$(declare -f $FUNCS)
	local VARS=$(declare -p DEBUG VERBOSE MACHINE MM_LIBS $VARS 2>/dev/null)
	if [ "$MM_DEBUG_LIB" ]; then
		# rsync lib to machine and load from there:
		# slower (takes ~1s) but reports line numbers correctly on errors.
		QUIET=1 SRC_DIR=lib    DST_DIR=/root/.mm DST_MACHINE=$MACHINE rsync_dir
		QUIET=1 SRC_DIR=libopt DST_DIR=/root/.mm DST_MACHINE=$MACHINE rsync_dir
		ssh_to bash -s <<< "
$VARS
$FUNCS
. /root/.mm/lib/all
$SCRIPT $ARGS
"
	else
		# include lib contents in the script:
		# faster but doesn't report line numbers correctly on errors in lib code.
		run ssh_to bash -s <<< "
$VARS
cd /opt/mm || exit 1
set -f # disable globbing
set -o pipefail
$(for LIB in ${MM_STD_LIBS[@]}; do cat $LIB; done)
$(for LIB in $MM_LIBS; do cat libopt/$LIB.sh; done)
$FUNCS
$SCRIPT $ARGS
"
	fi
}

md_ssh_script() { # [VARS=] DEPLOY=|MACHINE= "SCRIPT" ARGS...
	local SCRIPT=$1; shift
	checkvars SCRIPT-
	md_vars
	VARS="DEPLOY $VARS" ssh_script "
${R1[*]}
$SCRIPT" "$@"
}


# ssh config -----------------------------------------------------------------

ssh_hostkey() {
	ip_of "$1"; local MACHINE=$R2
	catfile var/machines/$MACHINE/.ssh_hostkey
}

ssh_hostkey_update() {
	ip_of "$MACHINE"; local IP=$R1; local MACHINE=$R2
	say "Updating SSH host fingerprint for machine: $MACHINE ..."
	must ssh-keyscan -4 -T 2 -t rsa $IP > var/machines/$MACHINE/.ssh_hostkey
}

ssh_mk_config_dir() {
	must mkdir -p $HOME/.ssh
	must chown $USER:$USER $HOME/.ssh
	must chmod 700 $HOME/.ssh
}

ssh_host_config_update_for_user() { # USER HOST KEYNAME KEY HOSTKEY [unstable_ip]
	local USER=$1 HOST=$2 KEYNAME=$3 KEY=$4 HOSTKEY=$5 UNSTABLE_IP=$6
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	checkvars USER HOST KEYNAME KEY- HOSTKEY-
	say "Configuring SSH key '$KEYNAME' for host '$HOST' for user '$USER' ..."

	ssh_mk_config_dir

	local KEYFILE=$HOME/.ssh/${KEYNAME}.id_rsa
	save "$KEY" $KEYFILE $USER 600

	local HOSTKEYFILE=$HOME/.ssh/${KEYNAME}.hostkey
	save "$HOSTKEY" $HOSTKEYFILE $USER 600

	local CONFIG=$HOME/.ssh/config
	touch "$CONFIG"
	local s=$(sed 's/^Host/\n&/' $CONFIG | sed '/^Host '"$HOST"'$/,/^$/d;/^$/d')
	s="$s
Host $HOST
  HostName $HOST
  IdentityFile $KEYFILE
  UserKnownHostsFile $HOSTKEYFILE "
	[ "$UNSTABLE_IP" ] && s+="
  CheckHostIP no"
	save "$s" $CONFIG $USER 600
}

ssh_usable_keyfile() { # [MACHINE=] -> FOUND_KEYFILE [MACHINE_KEYFILE]
	R2=
	[[ $MACHINE ]] && {
		R1=var/machines/$MACHINE/.ssh_key
		[[ -f $R1 ]] && return
		R2=$R1 # machine key file
	}
	R1=var/ssh_key
	[[ -f $R1 ]] && return
	checkfile $HOME/.ssh/id_rsa
}

ssh_pubkey_from_keyfile() { # KEYFILE
	local KEYFILE=$1
	checkvars KEYFILE
	R1=`must ssh-keygen -y -f "$KEYFILE"` || exit
}

ssh_pubkey_find() { # USER KEYMATCH
	local USER=$1 KEYMATCH=$2
	checkvars USER KEYMATCH
	local HOME=/home/$USER; [ $USER == root ] && HOME=/root
	cat $HOME/.ssh/authorized_keys | grep "$KEYMATCH"
}

ssh_device_pubkey() { # DEVICE
	local DEVICE=$1
	checkvars DEVICE
	must catfile devices/$DEVICE/ssh_pubkey
}

_ssh_pubkeys() { # [USERS]
	local USERS=$1
	[[ $USERS ]] || USERS=`echo root; ls -1 /home`
	for USER in $USERS; do
		local HOME=/home/$USER; [[ $USER == root ]] && HOME=/root
		local kf=$HOME/.ssh/authorized_keys
		[[ -f $kf ]] || continue
		local line
		while IFS= read -r line; do
			while read -r type key name; do
				[[ $key ]] || continue
				printf "%b\n" "$MACHINE $USER $type $key $name"
			done <<< "$line"
		done < $kf
	done
}
ssh_pubkeys() { # [USERS]
	local USERS=$1
	local FMT="%-10s %-10s %-10s %-22s %-10s %-10s\n"
	printf "$WHITE$FMT$ENDCOLOR" MACHINE USER TYPE KEY KEYNAME DEVICE
	declare -A map
	local device; for device in `ls var/devices`; do
		catfile var/devices/$device/ssh_pubkey || continue
		read -r type key name <<< "$R1"
		map["$type $key"]=$device
	done
	ssh_usable_keyfile; local KEYFILE=$R1
	ssh_pubkey_from_keyfile $KEYFILE; local MY_PUBKEY=$R1
	local machine user type key name
	QUIET=1 SSH_KEYFILE=$KEYFILE each_machine ssh_script "_ssh_pubkeys" "$USERS" \
		| while read -r machine user type key name; do
			device=${map["$type $key"]}
			printf "$FMT" $machine $user $type ${key: -20} "$name" ${device:-?}
		done
}

ssh_pubkey_update_for_user() { # USER PUBKEY [--remove]
	local USER=$1 PUBKEY=$2 REMOVE=$3
	checkvars USER PUBKEY-
	say "Adding SSH public key '...${PUBKEY: -20}' for user '$USER'..."
	local HOME=/home/$USER; [[ $USER == root ]] && HOME=/root
	[[ -d $HOME ]] || die "No home dir for user '$USER'"
	local ak=$HOME/.ssh/authorized_keys
	[[ -f $ak ]] || {
		say "Creating file $ak..."
		ssh_mk_config_dir
		must touch $ak
		must chmod 600 $ak
		must chown $USER:$USER $ak
	}
	local UP_PUBKEY=$(grep "$PUBKEY" $ak)
	if [[ $PUBKEY == --remove && $UP_PUBKEY == "" ]]; then
		say "Key not found."
	elif [[ $PUBKEY == $UP_PUBKEY ]]; then
		say "Key is the same."
	else
		remove_line "$PUBKEY" $ak
		if [[ $REMOVE != --remove ]]; then
			must append "$PUBKEY"$'\n' $ak
		fi
	fi
}
ssh_pubkey_update() { # PUBKEY [USERS] [--remove]
	local PUBKEY=$1 USERS=$3 REMOVE=$3
	checkvars PUBKEY-
	[[ $USERS ]] || USERS="$(echo root; machine_deploys)"
	for USER in $USERS; do
		ssh_pubkey_update_for_user $USER "$PUBKEY" $REMOVE
	done
}

# rsync ----------------------------------------------------------------------

# SRC_DIR= [FILE_LIST_FILE=] [DST_DIR=] [DST_USER=] [DST_GROUP=] [LINK_DIR=] [SRC_MACHINE=] [DST_MACHINE=] [PROGRESS=1] [DRY] [MOVE] [VERBOSE] rsync_cmd
rsync_cmd() {
	local SRC_DIR=$SRC_DIR
	local DST_DIR=${DST_DIR:-$SRC_DIR}
	local PROGRESS=$PROGRESS; [[ $TERM ]] || PROGRESS=
	checkvars SRC_DIR DST_DIR
	local LINK_DIR=$LINK_DIR
	if [[ $LINK_DIR && -d $LINK_DIR ]]; then
		LINK_DIR=$(realpath "$LINK_DIR") # --link-dest path must be absolute!
		checkvars LINK_DIR
	fi

	local SRC_MACHINE=$SRC_MACHINE; [[ $SRC_MACHINE ]] && { ip_of "$SRC_MACHINE"; SRC_MACHINE=$R2; SRC_DIR="root@$R1:$SRC_DIR"; }
	local DST_MACHINE=$DST_MACHINE; [[ $DST_MACHINE ]] && { ip_of "$DST_MACHINE"; DST_MACHINE=$R2; DST_DIR="root@$R1:$DST_DIR"; }
	[[ $SRC_MACHINE && $DST_MACHINE ]] && die "Can't copy between two remotes."
	local MACHINE=$SRC_MACHINE$DST_MACHINE

	sayn "Sync'ing${DRY:+ DRY}: '$SRC_DIR' -> '$DST_DIR'${LINK_DIR:+ lnk '$LINK_DIR'} ... "
	[[ $DRY ]] && local VERBOSE=1
	[[ $PROGRESS ]] && say

	local ssh_cmd; [[ $MACHINE ]] && ssh_cmd_opt; ssh_cmd=("${R1[@]}")

	# NOTE: use `foo/bar/./baz/qux` dot syntax to end up with `$DST_DIR/baz/qux` !
	R1=(rsync
		--recursive --relative --links --perms --times --devices --specials --hard-links --timeout=5
		${DELETE:+--delete}
		${PROGRESS:+--info=progress2}
		${LINK_DIR:+--link-dest="$LINK_DIR"}
		${MOVE:+--remove-source-files}
		${DST_USER:+--chown=$DST_USER:${DST_GROUP:-$DST_USER}}
		${FILE_LIST_FILE+--files-from="$FILE_LIST_FILE"}
		${DRY:+--dry-run}
		${VERBOSE:+-v}
	)
	[[ $ssh_cmd ]] && R1+=(-e "${ssh_cmd[*]}")
	R1+=("$SRC_DIR" "$DST_DIR")
}

rsync_dir() {
	rsync_cmd
	must "${R1[@]}"
	[[ $PROGRESS ]] || say OK
}
