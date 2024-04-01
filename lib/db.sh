# machines -------------------------------------------------------------------

machine_of() {
	checknosp "$1" "required: machine or deployment name"
	if [ -d var/deploys/$1 ]; then
		checkfile var/deploys/$1/machine
		R1=$(cat $R1)
	elif [ -d var/machines/$1 ]; then
		R1=$1
	else
		die "No machine or deploy named: '$1'"
	fi
}

ip_of() {
	machine_of "$1"; R2=$R1
	checkfile var/machines/$R2/public_ip
	R1=$(cat $R1)
}

mysql_root_pass() {
	machine_of "$1"; local MACHINE=$R1
	checkfile var/machines/$MACHINE/ssh_key; local ssh_key_file=$R1
	R1="$(sed 1d $ssh_key_file | head -1)"
	R1="${R1:0:32}"
}

machine_vars() {
	machine_of "$1"; local MACHINE=$R1
	mysql_root_pass "$MACHINE"; local MYSQL_ROOT_PASS="$R1"
	checkfile var/dhparam.pem; local DHPARAM="$(cat $R1)"
	checkfile var/machines/$MACHINE/vars; MACHINE_VARS="$(cat $R1)"
	checkfile var/machine_vars; MM_VARS="$(cat $R1)"
	local GIT_HOSTS=""
	local GIT_VARS=""
	pushd var/git_hosting
	local NAME
	for NAME in *; do
		checkfile $NAME/host; local HOST=$(cat $R1)
		checkfile $NAME/ssh_hostkey; local SSH_HOSTKEY="$(cat $R1)"
		checkfile $NAME/ssh_key; local SSH_KEY="$(cat $R1)"
		GIT_HOSTS="$GIT_HOSTS
$NAME"
		GIT_VARS="$GIT_VARS
${NAME^^}_HOST=$HOST
${NAME^^}_SSH_HOSTKEY=\"$SSH_HOSTKEY\"
${NAME^^}_SSH_KEY=\"$SSH_KEY\"
"
	done
	popd
	R1="
MACHINE=$MACHINE
DHPARAM=\"$DHPARAM\"
MYSQL_ROOT_PASS=\"$MYSQL_ROOT_PASS\"
$MACHINE_VARS
$MM_VARS
GIT_HOSTS=\"$GIT_HOSTS\"
$GIT_VARS
"
}

active_machines() {
	local MACHINE
	for MACHINE in `ls -1 var/machines`; do
		[ "$INACTIVE" != "" -o -f "var/machines/$MACHINE/active" ] && echo $MACHINE
	done
}

each_machine() { # [MACHINE] COMMAND ...
	local MDS="$1"; shift
	local MACHINES
	if [ "$MDS" ]; then
		local MD
		for MD in $MDS; do
			ip_of $MD
			MACHINES="$MACHINES"$'\n'"$R2"
		done
	else
		MACHINES="$(active_machines)"
	fi
	local CMD="$1"; shift
	for MACHINE in $MACHINES; do
		[ "$QUIET" ] || say "On machine $MACHINE:"; indent
		"$CMD" "$MACHINE" "$@"
		outdent
	done
}

# deploys --------------------------------------------------------------------

