# mm lib: functions reading var/machines and var/deploys on the mm machine.

# mm module ------------------------------------------------------------------

install_mm() {
	git_clone_for root git@github.com:allegory-software/many-machines2 /root/mm master
	# install globally
	must ln -sf /root/mm/mm      /usr/bin/mm
	must ln -sf /root/mm/mmd     /usr/bin/mmd
	must ln -sf /root/mm/lib/all /usr/bin/mmlib
	remove_line /root/mm/mm-autocomplete.sh /root/.bashrc
	append ". /root/mm/mm-autocomplete.sh" /root/.bashrc
}

version_mm() {
	(
	must cd /root/mm
	must git rev-parse --short HEAD
	)
}

# var dir ops ----------------------------------------------------------------

var_pack() { # FILE
	local FILE=${1:-var.tar.gz.gpg}
	checkvars FILE
	must chmod 440 var_secret
	on_exit run rm -f tmp/var.tar.gz
	must tar -czf tmp/var.tar.gz var
	must gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase-file var_secret tmp/var.tar.gz
	must mv tmp/var.tar.gz.gpg $FILE
	du -sh $FILE
}

var_unpack() { # FILE
	local FILE=${1:-var.tar.gz.gpg}
	checkvars FILE
	on_exit run rm -f tmp/var.tar.gz
	must gpg --decrypt --batch --yes --passphrase-file var_secret $FILE > tmp/var.tar.gz
	must rm -rf tmp/var
	must mkdir tmp/var
	on_exit run rm -rf tmp/var
	must tar xzf tmp/var.tar.gz -C tmp/var --overwrite
	must mv --backup=numbered tmp/var/var .
	must chmod 770 var
}

var_git_init() { # [REPO]
	local REPO=$1
	package_version git-crypt >/dev/null || package_install git-gcrypt
	must mkdir -p var
	(
	must cd var
	must chmod 770 .
	[[ -d .git ]] || git init
	[[ ! -f .gitattributes && ! $REPO ]] && {
		save "\
* filter=git-crypt diff=git-crypt
.gitattributes !filter !diff
" .gitattributes
	}
	[[ -f .git/git-crypt/keys/default ]] || must git-crypt init
	[[ $REPO ]] && {
		run git remote add origin $REPO
		git pull origin master
	}
	)
}

var_clone() { # REPO
	local REPO=$1
	checkvars REPO
	on_exit run rm -rf var.new
	git_clone_for root $REPO var.new
	must mv --backup=numbered var.new var
	must chmod 770 var
}

var_pull() {
	(
	must cd var
	must git pull
	)
}

var_push() { # [COMMIT_MSG]
	(
	must cd var
	must git add .
	must git commit -m "${COMMIT_MSG:-unimportant}"
	must git push
	)
}

var_unlock() { # KEY
	local KEY=$1
	checkvars KEY-
	package_version git-crypt >/dev/null || package_install git-gcrypt
	(
	must cd var
	on_exit run rm -f ../var_git_crypt_key
	printf "%s" "$KEY" | must base64 -d - > ../var_git_crypt_key
	must git-crypt unlock ../var_git_crypt_key
	)
}

var_lock_key() {
	(
	must cd var
	git-crypt export-key /proc/self/fd/1 | base64 -
	)
}

# machines and deploys db ----------------------------------------------------

check_machine() { # MACHINE
	checknosp "$1" "MACHINE required"
	[[ -d var/machines/$1 ]] || die "Machine unknown: $1"
}

check_deploy() { # DEPLOY
	checknosp "$1" "DEPLOY required"
	[[ -d var/deploys/$1 ]] || die "Deployment unknown: $1"
}

check_md_new_name() { # MACHINE|DEPLOY
	local NAME=$1
	checkvars NAME
	[[ ! -d var/deploys/$NAME  ]] || die "A deploy with this name already exists: '$NAME'."
	[[ ! -d var/machines/$NAME ]] || die "A machine with this name already exists: '$NAME'."
}

try_machine_of_deploy() {
	check_deploy "$1"
	R1=$(basename $(readlink var/deploys/$1/machine) 2>/dev/null)
}
machine_of_deploy() { # DEPLOY
	try_machine_of_deploy "$@"
	[[ $R1 ]] || die "No machine set for deploy: $1."
}

machine_of() { # MACHINE|DEPLOY -> MACHINE, , [DEPLOY]
	checknosp "$1" "MACHINE or DEPLOY required"
	if [[ -d var/deploys/$1 ]]; then
		machine_of_deploy $1; R3=$1
	elif [[ -d var/machines/$1 ]]; then
		R1=$1
	else
		die "No MACHINE or DEPLOY named: '$1'"
	fi
}

ip_of() { # MD -> IP, MACHINE, [DEPLOY]
	machine_of "$1"; R2=$R1
	checkfile var/machines/$R2/public_ip
	R1=$(cat $R1)
}

machine_is_active() {
	DEPLOY= md_var ACTIVE 0
	[[ $R1 != 0 ]]; return $?
}

deploy_is_active() {
	md_var ACTIVE 0
	[[ $R1 != 0 ]]; return $?
}

active_machines() {
	local S
	local MACHINE
	for MACHINE in `[ -d machines ] && ls -1 machines || ls -1 var/machines`; do
		if [[ $INACTIVE ]] || machine_is_active; then  S+=" $MACHINE"; fi
	done
	R1=$S
}

active_deploys() {
	local S
	local DEPLOY
	for DEPLOY in `ls -1 var/deploys`; do
		if [[ $INACTIVE ]] || deploy_is_active; then S+=" $DEPLOY"; fi
	done
	R1=$S
}

# NOTE: set NOALL=1 for dangerous commands. User will set ALL=1 to override.
# NOTE: set NOSUBPROC=1 to break on first error.
each_machine() { # [NOALL=1] [ALL=1] [NOSUBPROC=1] MACHINES= DEPLOYS= COMMAND ARGS...
	declare -A mm
	local M D
	local MACHINES="$MACHINES"
	for M in $MACHINES; do
		check_machine $M
		mm[$M]=1
	done
	for D in $DEPLOYS; do
		machine_of $D; M=$R1
		[[ ${mm[$M]} ]] && continue
		mm[$M]=1
		MACHINES+=" $M"
	done
	if [[ ${#mm[@]} == 0 ]]; then
		[[ $NOALL  && ! $ALL ]] && die "MACHINE(s) required"
		active_machines
		MACHINES="$R1"
	fi
	[[ ! $QUIET && ${#mm[@]} == 1 ]] && QUIET=1
	local CMD="$1"; shift
	local MACHINE
	for MACHINE in $MACHINES; do
		[[ $QUIET ]] || say "On machine $MACHINE:"
		if [[ $NOSUBPROC ]]; then
			"$CMD" "$@"
		else
			("$CMD" "$@")
		fi
	done
}

each_deploy() { # [NOALL=1] [ALL=1] [NOSUBPROC=1] MACHINES="" DEPLOYS= COMMAND ARGS...
	local DEPLOYS="$DEPLOYS"
	if [[ $DEPLOYS ]]; then
		for DEPLOY in $DEPLOYS; do
			check_deploy $DEPLOY
		done
	else
		[[ $NOALL && ! $ALL ]] && die "DEPLOY(s) required"
		active_deploys
		DEPLOYS=$R1
	fi
	local CMD=$1; shift
	for DEPLOY in $DEPLOYS; do
		try_machine_of_deploy $DEPLOY; local MACHINE=$R1
		[[ $QUIET ]] || say "On deploy $DEPLOY:"
		if [[ $NOSUBPROC ]]; then
			"$CMD" "$@"
		else
			("$CMD" "$@")
		fi
	done
}

_each_deploy_with_domain() {
	if md_var DOMAIN; then
		local DOMAIN=$R1
		(DOMAIN=$DOMAIN "$@")
	fi
}
each_deploy_with_domain() {
	each_deploy _each_deploy_with_domain "$@"
}

_each_deploy_with_ssl() {
	if md_var DOMAIN; then
		local DOMAIN=$R1
		md_var NOSSL && return
		(DOMAIN=$DOMAIN "$@")
	fi
}
each_deploy_with_ssl() {
	each_deploy _each_deploy_with_ssl "$@"
}

each_md() {
	if [[ $MM_DEPLOY ]]; then
		each_deploy "$@"
	else
		each_machine "$@"
	fi
}
