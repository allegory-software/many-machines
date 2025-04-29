# deploy backup & restore

backup_date() {
	R1=`date -u +%Y-%m-%d-%H-%M-%S`
}

parse_backup_date() {
	local s=${1%.*} # remove extension
	s=${s: -19} # keep date-time part
	local d=${s:0:10} # date part
	local t=${s:11} # time part
	t=${t//-/:}
	R1="$d $t"
}

datetime_to_timestamp() {
	R1=`date -d "$1" +%s`
}

rel_backup_date() { # FILE
	parse_backup_date "$1"; R2=$R1
	datetime_to_timestamp "$R1"
	timeago "$R1"
}

list_deploy_backups() {
	local FMT="%-10s %-20s %s\n"
	printf "$WHITE$FMT$ENDCOLOR" DEPLOY AGE DATE
	local DEPLOY
	for DEPLOY in `ls backups`; do
		for DATE in `ls -r backups/$DEPLOY`; do
			[[ -L backups/$DEPLOY/$DATE ]] && continue
			rel_backup_date "$DATE"; local AGE=$R1
			printf "$FMT" "$DEPLOY" "$AGE" "$DATE"
		done
	done
}

ssh_to_or() { # MACHINE=|DST_MACHINE= ...
	checkvars MACHINE? DST_MACHINE?
	if [[ $DST_MACHINE ]]; then
		run ssh_to_cmd "$@"
	elif [[ $MACHINE ]]; then
		run "$@"
	else
		die "MACHINE or DST_MACHINE required."
	fi
}

ssh_ln_file() { # MACHINE=|DST_MACHINE= TARGET_FILE LINK_FILE
	if [[ $DST_MACHINE ]]; then
		must ssh_to
	elif [[ $MACHINE ]]; then
		true
	else
		die "MACHINE or DST_MACHINE required."
	fi
}

# mysql backup from a remote deploy (MACHINE=, DEPLOY=) to this machine
# or from a local deploy (DEPLOY=) to a remote machine (DST_MACHINE=).
deploy_backup_mysql() { # MACHINE=|DST_MACHINE= DEPLOY= BACKUP_DIR=
	must ssh_to 'mkdir -p' "$BACKUP_DIR"
	if [[ $DST_MACHINE ]]; then
		PROGRES=1 mysql_backup_db $DEPLOY | MACHINE=$DST_MACHINE ssh_save_stdin $BACKUP_DIR/db.qp
	else
		ssh_script "PROGRESS=1 mysql_backup_db $DEPLOY" > $BACKUP_DIR/db.qp
	fi
}

deploy_restore_mysql() { # BACKUP_DIR= DST_MACHINE= DST_DEPLOY=
	checkvars BACKUP_DIR DST_MACHINE DST_DEPLOY
	local BACKUP_FILE=$BACKUP_DIR/db.qp
	checkfile $BACKUP_FILE
	say "Restoring mysql files from '$BACKUP_FILE' to '$DST_MACHINE:$DST_DEPLOY' ... "

	SRC_MACHINE= \
		SRC_DIR="$(dirname $BACKUP_FILE)/./$(basename $BACKUP_FILE)" \
		DST_DIR=/root/.mm/$DST_DEPLOY.$$.qp \
		PROGRESS=1 rsync_dir

	MACHINE=$DST_MACHINE must ssh_script "
		on_exit run rm -f $DST_DEPLOY.$$.qp
		mysql_restore_db $DST_DEPLOY $DST_DEPLOY.$$.qp
	"
}

# incremental files backup from a deploy (MACHINE=, DEPLOY=) to this machine
# or from a local deply (DEPLOY=) to a remote machine (DST_MACHINE=).
deploy_backup_app() { # MACHINE=|DST_MACHINE= DEPLOY= BACKUP_DIR= [PREV_BACKUP_DIR=]
	checkvars DEPLOY BACKUP_DIR PREV_BACKUP_DIR?
	md_varfile backup_files; local backup_files_file=$R1
	ssh_mkdir "$BACKUP_DIR"
	FILE_LIST_FILE=$backup_files_file \
		SRC_MACHINE=$MACHINE \
		DST_MACHINE=$DST_MACHINE \
		SRC_DIR=/home/$DEPLOY \
		DST_DIR=$BACKUP_DIR \
		LINK_DIR=$PREV_BACKUP_DIR \
		PROGRESS=1 rsync_dir
}

# restore a deploy from a backup from this machine.
deploy_restore_app() { # BACKUP_DIR= DST_MACHINE= DST_DEPLOY=
	checkvars BACKUP_DIR DST_MACHINE DST_DEPLOY
	checkdir $BACKUP_DIR
	say "Restoring app files from '$BACKUP_DIR' to '$DST_MACHINE:$DST_DEPLOY' ... "
	SRC_MACHINE= \
		SRC_DIR=$BACKUP_DIR/./. \
		DST_DIR=/home/$DST_DEPLOY \
		DST_USER=$DST_DEPLOY \
		PROGRESS=1 rsync_dir
}

md_backup() { # DST_MACHINE=|MACHINE= [DEPLOY=] [all|MODULE1 ...]
	local MD=${DEPLOY:-$MACHINE}
	checkvars MD
	backup_date; local DATE=$R1
	local BACKUP_DIR=backups/$MD/$DATE
	local PREV_BACKUP_DIR=backups/$MD/latest
	ssh_mkdir "$BACKUP_DIR"
	[[ -d $PREV_BACKUP_DIR ]] || PREV_BACKUP_DIR=
	[[ "$*" ]] && ssh_mkdir "$BACKUP_DIR"
	_md_backup "$@"; [[ $? == 2 ]] && { R1=; return 2; }
	ln_file $DATE backups/$MD/latest
	R1=$DATE
}

md_restore() { # MD= DATE= [DST_MD=] [all|MODULE1 ...]
	checkvars MD DATE DST_MD?
	if [[ $DATE == latest ]]; then
		DATE=`readlink backups/$MD/latest` \
			|| die "No latest backup for '$MD'"
	fi
	[[ $DST_MD ]] || DST_MD=$MD
	machine_of     $MD ; local     MACHINE=$R1     DEPLOY=$R2
	machine_of $DST_MD ; local DST_MACHINE=$R1 DST_DEPLOY=$R2
	local BACKUP_DIR=backups/$MD/$DATE
	[[ "$*" ]] && MACHINE=$DST_MACHINE DEPLOY=$DST_DEPLOY md_stop all
	_md_restore "$@"
	[[ "$*" ]] && MACHINE=$DST_MACHINE DEPLOY=$DST_DEPLOY md_start all
}

# remove old backups according to configured retention policy.
md_backups_sweep() {
	mm_var backup_min_age_days     ; local min_age_s=$(( R1 * 3600 * 24 ))
	mm_var backup_min_free_disk_gb ; local min_free_kb=$(( R1 * 1024 * 1024 ))

	local free_kb=`df -l / | awk '(NR > 1) {print $3}'`
	dir_lean_size backups; local used_kb=$(( R1 / 1024 ))
	local must_free=$(( (min_free_kb - free_kb) * 1024 ))
	(( must_free < 0 )) && return 0

	kbytes $must_free
	say "Must free: $R1"

	local d f
	(
	local f
	local now=`date -u +%s`
	for f in `ls backups`; do
		[[ -L backups/$f ]] && continue
		parse_backup_date $f
		datetime_to_timestamp "$R1"
		local d=$R1
		(( d + min_age > now )) && continue
		printf "%s %s\n" $R1 $f
	done
	) | sort -k1n | while read d f; do
		local fsize=`stat -c %s backups/$f`
		DRY=1 rm_file /root/mm/backups/$f
		must_free=$(( must_free - fsize ))
		(( must_free < 0 )) && break
	done
}

deploy_move() { # DEPLOY= [LATEST=1] DST_MACHINE=
	checkvars DEPLOY DST_MACHINE
	local DST_MACHINE=$DST_MACHINE; machine_of $DST_MACHINE; DST_MACHINE=$R1

	# backup the deploy or use the latest backup.
	local DATE
	if [[ $LATEST ]]; then
		DATE=`readlink backups/$DEPLOY/latest` \
			|| die "No latest backup for deploy '$DEPLOY'"
	else
		deploy_backup
		DATE=$R1
	fi

	# backup SSL cert if any.
	acme_cert_cerfile; [[ -f $R1 ]] && acme_cert_backup

	ln_file ../../machines/$DST_MACHINE var/deploys/$DEPLOY/machine

	# restore SSL cert if any.
	(MACHINE=$DST_MACHINE acme_cert_restore)

	# install the deploy.
	MACHINE=$DST_MACHINE md_install all

	# restore the deploy data over the fresh install.
	deploy_restore
}

md_move() {
	if [[ $DEPLOY ]]; then
		deploy_move "$@"
	else
		machine_move "$@"
	fi
}

install_backup_user() {
	local user=backup
	say "Creating rsync backup user '$user' ... "

	user_exists $user || must adduser --disabled-password --shell /usr/sbin/nologin $backup

	must mkdir -p /home/$user/.ssh
	must chown $user:$user /home/$user/.ssh
	chmod 700 /home/$user/.ssh

	save '
#!/bin/bash
case "$SSH_ORIGINAL_COMMAND" in
	rsync\ --server*\ --sender*) echo "Pull not allowed"; exit 1 ;;
	rsync\ --server*) exec $SSH_ORIGINAL_COMMAND ;;
	*) echo "Access denied"; exit 1 ;;
esac
' /home/$user/backup $user +x

	local pubkey=""

	save "command=/home/$user/backup,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty $pubkey
" /home/$user/.ssh/authorized_keys $user 660

	say OK
}
