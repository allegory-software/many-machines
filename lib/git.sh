#use die

# make repeated git pulls faster by reusing SSH connections.
# ...alas, it doesn't work, gives `mux_client_request_session: read from master failed: Broken pipe`
# export GIT_SSH_COMMAND="ssh -o ControlMaster=auto -o ControlPersist=10 -o ControlPath=~/.ssh/control-%h-%p-%r-git"

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

git_clone_for() { # USER REPO DIR VERSION LABEL
	local USER="$1"
	local REPO="$2"
	local DIR="$3"
	local VERSION="$4"
	local LABEL="$5"
	checkvars USER REPO DIR
	[ "$VERSION" ] || VERSION=master
	say "Pulling $DIR $VERSION ..."
	(
	must mkdir -p $DIR
	must chown -R root:root $DIR
	must cd $DIR
	[ -d .git ] || must git init -q
	git ls-remote --exit-code origin 2>/dev/null && must git remote remove origin
	run  git remote rm  origin 2>/dev/null
	must git remote add origin $REPO
	must git -c advice.objectNameWarning=false fetch --depth=1 -q origin "$VERSION:refs/remotes/origin/$VERSION"
	must git -c advice.detachedHead=false checkout -q -B "$VERSION" "origin/$VERSION"
	[ "$LABEL" ] && echo "${LABEL}_commit=$(git rev-parse --short HEAD)"
	exit 0
	)
	local ret=$?
	must chown -R $USER:$USER $DIR
	[ $ret != 0 ] && exit
}

mgit_install() {
	git_clone_for root git@github.com:capr/multigit.git /opt/mgit
	must ln -sf /opt/mgit/mgit /usr/local/bin/mgit
}
