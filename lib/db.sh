# machines -------------------------------------------------------------------

machine_of() {
	checknosp "$1" "MACHINE or DEPLOY required"
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
	checkfile var/machines/$MACHINE/mm_ssh_key; local ssh_key_file=$R1
	R1="$(sed 1d $ssh_key_file | head -1)"
	R1="${R1:0:32}"
}

git_vars() {
	local GIT_HOSTS=
	local GIT_VARS=
	pushd var/git_hosting
	local NAME
	for NAME in *; do
		catfile $NAME/host        ; local HOST=$R1
		catfile $NAME/ssh_hostkey ; local SSH_HOSTKEY="$R1"
		catfile $NAME/ssh_key     ; local SSH_KEY="$R1"
		GIT_HOSTS="$GIT_HOSTS $NAME"
		GIT_VARS="$GIT_VARS
${NAME^^}_HOST=$HOST
${NAME^^}_SSH_HOSTKEY=\"$SSH_HOSTKEY\"
${NAME^^}_SSH_KEY=\"$SSH_KEY\"
"
	done
	popd
	R1="
GIT_HOSTS=\"$GIT_HOSTS\"
$GIT_VARS
"
}

machine_vars() {
	local VARS=
	machine_of "$1"; local MACHINE=$R1
	mysql_root_pass "$MACHINE"; local MYSQL_ROOT_PASS="$R1"
	catfile var/dhparam.pem                   ; local DHPARAM="$R1"
	catfile var/mm_ssh_key.pub                ; local MM_SSH_PUBKEY="$R1"
	git_vars                                  ; VARS+=$'\n'"$R1"
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

check_deploy() {
	checknosp "$1" "DEPLOY required"
	[ -d var/deploys/$1 ] || die "deployment unknown: $1"
}

machine_of_deploy() {
	check_deploy "$1"
	catfile var/deploys/$1/machine
}

deploy_vars() {
	local VARS=
	local DEPLOY="$1"; checkvars DEPLOY
	machine_of_deploy $DEPLOY                 ; local MACHINE=$R1
	catfile var/deploys/$DEPLOY/repo          ; local REPO=$R1
	catfile var/deploys/$DEPLOY/app           ; local APP=$R1
	catfile var/deploys/$DEPLOY/app_version ""; local APP_VERSION=$R1
	catfile var/deploys/$DEPLOY/sdk_version ""; local SDK_VERSION=$R1
	catfile var/deploys/$DEPLOY/env         ""; local ENV=$R1
	catfile var/deploys/$DEPLOY/domain      ""; local DOMAIN=$R1
	catfile var/deploys/$DEPLOY/http_port     ; local HTTP_PORT=$R1
	catfile var/deploys/$DEPLOY/mysql_pass    ; local MYSQL_PASS="$R1"
	catfile var/deploys/$DEPLOY/secret        ; local SECRET="$R1"
	catfile var/mm_ssh_key.pub                ; local MM_SSH_PUBKEY="$R1"

	# custom vars
	catfile var/deploy_vars                 ""; VARS+=$'\n'"$R1"
	catfile var/deploys/$DEPLOY/var_files   ""; local VAR_FILES="$R1"
	local FILE; for FILE in $VAR_FILES; do
		catfile var/$FILE; VARS+=$'\n'"$R1"
	done
	catfile var/deploys/$DEPLOY/vars        ""; VARS+=$'\n'"$R1"

	git_vars                                  ; VARS+=$'\n'"$R1"
	R1="$VARS
DEPLOY=$DEPLOY
MACHINE=$MACHINE
MM_SSH_PUBKEY=\"$MM_SSH_PUBKEY\"
APP=$APP
APP_VERSION=${APP_VERSION:-master}
SDK_VERSION=${SDK_VERSION:-dev}
ENV=${ENV:-dev}
DOMAIN=$DOMAIN
HTTP_PORT=$HTTP_PORT
MYSQL_PASS=\"$MYSQL_PASS\"
SECRET=\"$SECRET\"
"
}
