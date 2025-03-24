# ssh lib: ssh config and operation wrappers.

ssh_cmd_opt() { # MACHINE=
	R1=(ssh
-o ConnectTimeout=3
-o PreferredAuthentications=publickey
-o UserKnownHostsFile=var/machines/$MACHINE/.ssh_hostkey
-o ControlMaster=auto
-o ControlPath=$HOME/.ssh/control-%h-%p-%r
-o ControlPersist=600
)
	# try current key but also any old keys, in case the pubkey was not updated
	# on the remote host when the privkey was renewed.
	set +f # enable globbing
	local a=($HOME/.ssh/id_rsa.~* $HOME/.ssh/id_rsa)
	set -f
	local i n=${#a[@]}
	for ((i=n-1; i>=0; i--)); do
		R1+=(-i ${a[$i]})
	done

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
	local VARS=$(declare -p DEBUG VERBOSE DRY MACHINE MM_LIBS $VARS 2>/dev/null)
	if [ "$MM_DEBUG_LIB" ]; then
		# rsync lib to machine and load from there:
		# slower (takes ~1s) but reports line numbers correctly on errors.
		QUIET=1 SRC_DIR=lib    DST_DIR=/root/.mm DST_MACHINE=$MACHINE rsync_dir
		QUIET=1 SRC_DIR=libopt DST_DIR=/root/.mm DST_MACHINE=$MACHINE rsync_dir
		run ssh_to bash -s <<< "
$VARS
$FUNCS
. /root/.mm/lib/all
mkdir -p /root/.mm/tmp
cd /root/.mm || exit 1
$SCRIPT $ARGS
"
	else
		# include lib contents in the script:
		# faster but doesn't report line numbers correctly on errors in lib code.
		run ssh_to bash -s <<< "
$VARS
set -f # disable globbing
shopt -s nullglob
set -o pipefail
mkdir -p /root/.mm/tmp
cd /root/.mm || exit 1
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
	local MACHINE=$MACHINE
	if [[ $DEPLOY && ! $MACHINE ]]; then
		machine_of $DEPLOY
		MACHINE=$R1
	fi
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
	save "$KEY"$'\n' $KEYFILE $USER 600 # \n is important!

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

ssh_pubkey() {
	R1=`must ssh-keygen -y -f $HOME/.ssh/id_rsa` || exit
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
				printf "%s\n" "$MACHINE $USER $type $key $name"
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
	ssh_pubkey; local MY_PUBKEY=$R1
	local machine user type key name
	QUIET=1 each_machine ssh_script "_ssh_pubkeys" "$USERS" \
		| while read -r machine user type key name; do
			device=${map["$type $key"]}
			printf "$FMT" $machine $user $type ${key: -20} "$name" ${device:-?}
		done
}

_ssh_pubkey_add() {
	if [[ -f $AK_FILE ]]; then
		remove_line "$PUBKEY" $AK_FILE
		append "$PUBKEY"$'\n' $AK_FILE
	else
		ssh_mk_config_dir
		save "$PUBKEY"$'\n' $AK_FILE
	fi
}
_ssh_pubkey_remove() {
	remove_line "$PUBKEY" $AK_FILE
}
_ssh_pubkey_do() { # fn "PUBKEY" [USERS]
	local fn=$1 PUBKEY=$2 USERS=$3
	checkvars PUBKEY-
	[[ $USERS ]] || USERS="$(echo root; machine_deploys)"
	for USER in $USERS; do
		local HOME=/home/$USER; [[ $USER == root ]] && HOME=/root
		local AK_FILE=$HOME/.ssh/authorized_keys
		$fn
	done
}
ssh_pubkey_add()    { _ssh_pubkey_do _ssh_pubkey_add    "$@"; }
ssh_pubkey_remove() { _ssh_pubkey_do _ssh_pubkey_remove "$@"; }

# rsync ----------------------------------------------------------------------

# SRC_DIR= [FILE_LIST_FILE=] [DST_DIR=] [SRC_MACHINE=] [DST_MACHINE=] \
#   [MOVE=1] [NODELETE=1] [LINK_DIR=] [DST_USER=] [DST_GROUP=] \
#   [PROGRESS=1] [DRY=1] [VERBOSE=1] rsync_cmd
rsync_cmd() {
	local SRC=$SRC_DIR
	local DST=${DST_DIR:-$SRC_DIR}
	local PROGRESS=$PROGRESS; [[ $TERM ]] || PROGRESS=
	checkvars SRC DST
	[[ $LINK_DIR ]] && checkvars LINK_DIR

	[[ $SRC_MACHINE ]] && { ip_of "$SRC_MACHINE"; SRC="root@$R1:$SRC"; }
	[[ $DST_MACHINE ]] && { ip_of "$DST_MACHINE"; DST="root@$R1:$DST"; }
	[[ $SRC_MACHINE && $DST_MACHINE ]] && die "Can't copy between two remotes."
	local MACHINE=$SRC_MACHINE$DST_MACHINE

	sayn "Sync'ing${DRY:+ DRY}: '${SRC_MACHINE:+$SRC_MACHINE:}$SRC_DIR' -> '${DST_MACHINE:+$DST_MACHINE:}$DST_DIR'${LINK_DIR:+ lnk '$LINK_DIR'} ... "
	[[ $DRY ]] && local VERBOSE=1
	[[ $PROGRESS ]] && say

	local ssh_cmd; [[ $MACHINE ]] && ssh_cmd_opt; ssh_cmd=("${R1[@]}")

	# NOTE: use `foo/bar/./baz/qux` dot syntax to end up with `$DST_DIR/baz/qux` !
	R1=(rsync
		--recursive --relative --links --perms --times --devices --specials --hard-links --timeout=5
		${PROGRESS:+--info=progress2}
		${LINK_DIR:+--link-dest="$LINK_DIR"}
		${MOVE:+--remove-source-files}
		${DST_USER:+--chown=$DST_USER:${DST_GROUP:-$DST_USER}}
		${FILE_LIST_FILE+--files-from="$FILE_LIST_FILE"}
		${DRY:+--dry-run}
		${VERBOSE:+-v}
	)
	[[ $NODELETE ]] || R1+=(--delete)
	[[ $ssh_cmd ]] && R1+=(-e "${ssh_cmd[*]}")
	R1+=("$SRC" "$DST")
}

rsync_dir() {
	rsync_cmd
	must "${R1[@]}"
	[[ $PROGRESS ]] || say OK
}

rsync_upload() { # SRC_DIR DST_DIR
	checkvars MACHINE
	DST_MACHINE=$MACHINE SRC_DIR=$1 DST_DIR=$2 rsync_dir
}

rsync_download() { # SRC_DIR DST_DIR
	checkvars MACHINE
	SRC_MACHINE=$MACHINE SRC_DIR=$1 DST_DIR=$2 rsync_dir
}
