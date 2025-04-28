# user admin ops: runs as root on a machine administered by mm.

user_exists() { # USER
	local user=$1
	checkvars user
	id -u $user &>/dev/null
}

user_create() { # USER
	local user=$1
	checkvars user
	sayn "Creating user '$user' ... "
	user_exists $user || must useradd -m $user
	must chsh -s /bin/bash $user
	must chown $user:$user /home/$user
	must chmod 750 /home/$user
	say OK
}

user_remove_sudo() {
	local user=$1
	checkvars user
	sayn "Removing user '$user' from sudo group ... "
	id $user | grep -q sudo || { say "wasn't in it"; return 0; }
	must gpasswd -d $user sudo
	say OK
}

user_lock_pass() { # USER
	local user=$1
	checkvars user
	sayn "Locking password for user '$user' ... "
	must passwd -l $user >/dev/null
	say OK
}

user_check_can_remove() {
	ps -u "$1" &>/dev/null && die "User $1 still has running processes."
}

user_in_group() { # USER GROUP
	local user=$1 group=$2
	checkvars user group
	id -nG $user | grep -qw $group
}

user_remove() { # USER
	local user="$1"
	checkvars user
	user_check_can_remove $user
	local u
	for u in $(getent group $user | cut -d: -f4 | tr ',' ' '); do
		sayn "Removing user '$u' from group '$user' ... "
		user_in_group "$u" $user && must deluser --quiet "$u" $user && say OK || say "not found"
	done
	sayn "Removing user '$user' ... "
	user_exists $user && must userdel -r $user && say OK || say "not found"
}

user_rename() { # OLD_USER NEW_USER
	local old_user=$1
	local new_user=$2
	checkvars old_user new_user
	sayn "Renaming user '$old_user' to '$new_user' ... "
	user_exists $old_user || die "User not found: $old_user"
	user_exists $new_user && die "User already exists: $new_user"
	user_check_can_remove $old_user

	must usermod -l "$new_user" "$old_user"
	must usermod -d /home/$new_user -m $new_user
	must groupmod -n $new_user $old_user

	say OK
}

# list users with a login shell
_list_users() {
	local user pass rest
	declare -A map
	while IFS=: read -r user pass rest; do
		map[$user]=$pass
	done < /etc/shadow
	local user pass uid gid gecos home shell
	while IFS=: read -r user pass uid gid gecos home shell; do
		[[ $shell == */nologin ]] && continue
		[[ $shell == */false ]] && continue
		echo $MACHINE
		[[ $user == $DEPLOY || -d /home/$user/app ]] && echo $user || echo '*'
		echo $user
		[[ ${map[$user]} =~ ^[!*] ]] && echo ${LIGHTGRAY}yes$ENDCOLOR || echo ${LIGHTRED}NO!$ENDCOLOR
		echo $uid
		echo $gid
		echo $shell
	done  < /etc/passwd
}
list_users() {
	md_ssh_list _list_users \
		"%-10s %-10s %-10s %-10s %-20s" \
		"USER LOCKED UID GID SHELL" \
		"%-10s %-19s %-10s %-10s %-20s"
}
