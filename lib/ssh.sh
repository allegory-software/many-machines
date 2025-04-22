# ssh lib: ssh config and operation wrappers.

# common ssh options for ssh, autossh, sshfs and rsync
ssh_cmd_opt() { # MACHINE= [REMOTE_PORT=]
	R1=(
		-o ConnectTimeout=3
		-o PreferredAuthentications=publickey
		-o UserKnownHostsFile=/root/mm/var/machines/$MACHINE/.ssh_hostkey
	)
	# try current key but also any old keys, in case the pubkey was not updated
	# on the remote host when the privkey was renewed.
	set +f # enable globbing
	local a=($HOME/.ssh/id_rsa.~* $HOME/.ssh/id_rsa)
	set -f
	local i n=${#a[@]}
	for ((i=n-1; i>=0; i--)); do
		R1+=(-o IdentityFile=${a[$i]})
	done
	[[ $REMOTE_PORT ]] || R1+=(
		-o ControlMaster=auto
		-o ControlPath=$HOME/.ssh/control-$MACHINE-$USER
		-o ControlPersist=600
	)
}

ssh_to() { # [AS_USER=] [AS_DEPLOY=1] MACHINE= [REMOTE_PORT=] [LOCAL_PORT=] [REMOTE_DIR=] [SSH_TTY=1] [COMMAND ARGS...]
	local LOCAL_PORT=${LOCAL_PORT:-$REMOTE_PORT}
	[[ $AS_DEPLOY && $DEPLOY ]] && local AS_USER=$DEPLOY
	[[ $1 ]] || local MM_SSH_TTY=1
	ip_of "$MACHINE"; local HOST=$R1
	local cmd
	if [[ $REMOTE_PORT ]]; then # tunnel
		lsof -i :$LOCAL_PORT >/dev/null && die "Port already bound: $LOCAL_PORT"
		ssh_cmd_opt; cmd=(autossh "${R1[@]}" -fN -M 0 -L ${LOCAL_PORT:-$REMOTE_PORT}:localhost:$REMOTE_PORT)
	elif [[ $REMOTE_DIR ]]; then # mount
		mountpoint -q $MOUNT_DIR && die "Already mounted: $MOUNT_DIR"
		ssh_cmd_opt; cmd=(sshfs -o reconnect "${R1[@]}" root@$HOST${REMOTE_DIR:+:$REMOTE_DIR} $MOUNT_DIR)
	else # shell
		ssh_cmd_opt
		[[ $MM_SSH_TTY ]] && R1+=(-t) || R1+=(-o BatchMode=yes)
		cmd=(ssh "${R1[@]}" $HOST)
	fi
	quote_args "$@"; local args=("${R1[@]}")
	local sudo; [[ $AS_USER ]] && { [[ $1 ]] && sudo="sudo -i -u $AS_USER" || sudo="su - $AS_USER"; }
	# NOTE: ssh relays the remote command's exit code back to the user,
	# so it's hard to tell when ssh fails from when the command fails,
	# so all scripts must exit with code 0, anything else will cause an abort.
	run "${cmd[@]}" $sudo "${args[@]}" || die "MACHINE=$MACHINE ssh_to: [$?]"
}

ssh_script() { # [AS_USER=] [AS_DEPLOY=1] [MM_LIBS="lib1 ..."] MACHINE= [FUNCS="fn1 ..."] [VARS="VAR1 ..."] "SCRIPT" ARGS...
	local SCRIPT=$1; shift
	checkvars MACHINE SCRIPT-
	quote_args "$@"; local ARGS="${R1[*]}"
	[[ $FUNCS ]] && local FUNCS=$(declare -f $FUNCS)
	local VARNAMES="DEBUG VERBOSE DRY MACHINE MM_LIBS $VARS"
	local VARS=$(declare -p $VARNAMES 2>/dev/null)
	debug "-------------------------------------------------------"
	debug "ssh_to ARGS   : $ARGS"
	debug "ssh_to SCRIPT :"
	debug "-------------------------------------------------------"
	debug "$VARS"
	debug "$SCRIPT"
	debug "-------------------------------------------------------"
	if [ "$MM_DEBUG_LIB" ]; then
		# rsync lib to machine and load from there:
		# slower (takes ~1s) but reports line numbers correctly on errors.
		local DST_DIR=/root/.mm
		local DST_USER=root
		[[ $AS_USER ]] && {
			DST_DIR=/home/$AS_USER/.mm
			DST_USER=$AS_USER
		}
		QUIET=1 SRC_DIR=lib    DST_MACHINE=$MACHINE rsync_dir
		QUIET=1 SRC_DIR=libopt DST_MACHINE=$MACHINE rsync_dir
		local code="
$VARS
$FUNCS
. ~/.mm/lib/all
cd ~/.mm || exit 1
$SCRIPT $ARGS
"
		run ssh_to bash -s <<< "$code"
	else
		# include lib contents in the script:
		# faster but doesn't report line numbers correctly on errors in lib code.
		run ssh_to bash -s <<< "
$VARS
set -f # disable globbing
shopt -s nullglob
set -o pipefail
mkdir -p ~/.mm
cd ~/.mm || exit 1
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

ssh_tunnel_kill() { # LOCAL_PORT
	local LOCAL_PORT=$1
	checkvars LOCAL_PORT
	lsof -i :$LOCAL_PORT -sTCP:LISTEN -nP | awk '/ssh/ { print $2 }' | xargs kill
}

# TODO: make this safe with temp file!
ssh_save() { # S FILE [USER] [MODE]
	local s=$1 file=$2
	checkvars s- file
	sayn "Saving ${#s} bytes to remote file: '$file' ... " # TODO: ${user:+ user=$user}${mode:+ mode=$mode} ... "
	# use bash crazy feature of getting stdin after encountering 'exit'.
	printf "mkdir -p \`dirname $file\` && cat > $file; exit$s" | dry ssh_to bash -s
	say OK
}

ssh_lean_script() { # "SCRIPT"
	printf "$1" | ssh_to bash -s
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

ssh_pubkey() { # [USER=]
	local USER=${1:-$USER}
	checkvars USER
	local HOME; [[ $USER == root ]] && HOME=/root || HOME=/home/$USER
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

# SRC_DIR= [FILE_LIST_FILE=] [FILE_LIST=] [DST_DIR=] [SRC_MACHINE=] [DST_MACHINE=] \
#   [MOVE=1] [NODELETE=1] [LINK_DIR=] [DST_USER=] [DST_GROUP=] \
#   [PROGRESS=1] [DRY=1] [VERBOSE=1] rsync_dir
rsync_dir() {
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

	local ssh_cmd; [[ $MACHINE ]] && { ssh_cmd_opt; ssh_cmd=(ssh "${R1[@]}"); }

	# NOTE: use `foo/bar/./baz/qux` dot syntax to end up with `$DST_DIR/baz/qux` !
	R1=(rsync
		--recursive --relative --links --perms --times --devices --specials --hard-links --timeout=5
		--ignore-missing-args
		${PROGRESS:+--info=progress2}
		${LINK_DIR:+--link-dest="$LINK_DIR"}
		${MOVE:+--remove-source-files}
		${DST_USER:+--chown=$DST_USER:${DST_GROUP:-$DST_USER}}
		${FILE_LIST_FILE+--files-from="$FILE_LIST_FILE"}
		${DRY:+--dry-run}
		${VERBOSE:+-v}
	)
	[[ $FILE_LIST ]] && R1+=()
	[[ $NODELETE ]] || R1+=(--delete)
	[[ $ssh_cmd ]] && R1+=(-e "${ssh_cmd[*]}")
	if [[ $FILE_LIST ]]; then
		sayn "(with FILE_LIST) ... "
		must "${R1[@]}" --files-from=<(printf "%s\n" "$FILE_LIST") "$SRC" "$DST"
	else
		must "${R1[@]}" "$SRC" "$DST"
	fi
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
