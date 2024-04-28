# git lib: git wrappers...

# make repeated git pulls faster by reusing SSH connections.
export GIT_SSH_COMMAND="ssh -o ConnectTimeout=3 -o ControlMaster=auto -o ControlPath=~/.ssh/control-%h-%p-%r -o ControlPersist=600"

install_git() {
	package_install git
	say; say "Configuring git for pushing..."
	git_config_default_branch master
	git_config_user "mm@allegory.ro" "Many Machines"
	git_keys_update
	git_install_git_up
}

git_config_default_branch() {
	checknosp "$1"
	git config --global init.defaultBranch $1
}

git_install_git_up() {
	say "Installing 'git up' command..."
	local git_up=/usr/lib/git-core/git-up
	local s='
msg="$1"; [ "$msg" ] || msg="unimportant"
git add -A .
git commit -m "$msg"
git push
'
	must save "$s" $git_up
	must chmod +x $git_up

	# sneak that in here...
	git config --global alias.st status
}

git_config_user() { # email name
	must git config --global user.email "$1"
	must git config --global user.name "$2"
}

git_clone_for() { # USER REPO DIR [VERSION=master]
	local USER="$1"
	local REPO="$2"
	local DIR="$3"
	local VERSION="$4"
	local LABEL="$5"
	checkvars USER REPO DIR
	[ "$VERSION" ] || VERSION=master
	say "Pulling $DIR $VERSION ..."
	(
	local QUIET; [[ $DEBUG ]] || QUIET=-q
	must mkdir -p $DIR
	must chown -R root:root $DIR
	must cd $DIR
	[ -d .git ] || must git init $QUIET
	run  git remote rm  origin 2>/dev/null
	must git remote add origin $REPO
	must git -c advice.objectNameWarning=false fetch --depth=1 $QUIET origin "$VERSION:refs/remotes/origin/$VERSION"
	must git -c advice.detachedHead=false checkout $QUIET -B "$VERSION" "origin/$VERSION"
	local commit=$(must git rev-parse --short HEAD)
	say "Done. Now at: $commit"
	[[ $SUBMODULES ]] && {
		local SUB_PATH
		for SUB_PATH in $SUBMODULES; do
			must innermost_subpath_with_file .gitmodules $PWD/$SUB_PATH
			(
			say "Pulling $R1/$R2 ..."
			must cd $R1
			must git submodule update $QUIET --init --remote $R2
			local commit=$(must cd $R2; must git rev-parse --short HEAD)
			say "Done. Now at: $commit"
			) || exit
		done
	}
	exit 0
	)
	local ret=$?
	must chown -R $USER:$USER $DIR
	[ $ret != 0 ] && exit $ret
}

install_mgit() {
	git_clone_for root git@github.com:capr/multigit.git /opt/mgit
	must ln -sf /opt/mgit/mgit /usr/local/bin/mgit
}

git_vars() { # MACHINE
	local VARS=()
	cat_varfiles var/machines/$1 git_hosts; VARS+=("${R1[@]}")
	cat_varfile var/machines/$1 git_hosts; local GIT_HOSTS="$R1"
	local gh
	for gh in $GIT_HOSTS; do
		cat_varfiles var/machines/$1 \
			git_${gh}_host \
			git_${gh}_ssh_hostkey \
			git_${gh}_ssh_key
		VARS+=("${R1[@]}")
	done
	R1=("${VARS[@]}")
}

_git_keys_update_for_user() { # USER
	local USER="$1"
	checkvars USER GIT_HOSTS-
	for NAME in $GIT_HOSTS; do
		say "Updating git key '$NAME' for user '$USER' ..."
		local -n HOST=GIT_${NAME^^}_HOST
		local -n SSH_KEY=GIT_${NAME^^}_SSH_KEY
		local -n SSH_HOSTKEY=GIT_${NAME^^}_SSH_HOSTKEY
		checkvars HOST SSH_KEY- SSH_HOSTKEY-
		ssh_host_key_update_for_user $USER $HOST mm_$NAME "$SSH_KEY" "$SSH_HOSTKEY" unstable_ip
	done
}
git_keys_update() { # [USERS]
	local USERS="$1"
	[ "$USERS" ] || USERS="$(echo root; machine_deploys)"
	for USER in $USERS; do
		_git_keys_update_for_user $USER
	done
}
