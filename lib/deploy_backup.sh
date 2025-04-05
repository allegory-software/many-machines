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

deploy_mysql_backup() { # MACHINE= DEPLOY= [BACKUP_FILE]
	local BACKUP_FILE=${1:-/dev/stdout}
	checkvars MACHINE DEPLOY
	ssh_script "mysql_backup_db $DEPLOY" > $BACKUP_FILE
}

deploy_mysql_restore() { # BACKUP_FILE DST_MACHINE DST_DB
	local BACKUP_FILE=$1 DST_MACHINE=$2 DST_DB=$3
	checkvars BACKUP_FILE DST_MACHINE DST_DB
	checkfile $BACKUP_FILE
	machine_of "$DST_MACHINE"; local DST_MACHINE=$R1

	SRC_MACHINE= DST_MACHINE=$DST_MACHINE \
		SRC_DIR="$(dirname $BACKUP_FILE)/./$(basename $BACKUP_FILE)" \
		DST_DIR=/root/.mm/$DST_DB.$$.qp \
		PROGRESS=1 rsync_dir

	MACHINE=$DST_MACHINE ssh_script "
		on_exit run rm -f $DST_DB.$$.qp
		mysql_restore_db $DST_DB $DST_DB.$$.qp
	"
}

deploy_files_backup() { # MACHINE= DEPLOY= BACKUP_DIR [PREV_BACKUP_DIR]
	local BACKUP_DIR=$1 PREV_BACKUP_DIR=$2
	checkvars MACHINE DEPLOY BACKUP_DIR
	md_varfile backup_files; local backup_files_file=$R1
	local PDIR=$PREV_BACKUP_DIR
	[[ -d PDIR ]] && PDIR=`realpath $PDIR`
	must mkdir -p $BACKUP_DIR
	FILE_LIST_FILE=$backup_files_file \
		SRC_MACHINE=$MACHINE \
		DST_MACHINE= \
		SRC_DIR=/home/$DEPLOY \
		DST_DIR=$BACKUP_DIR \
		LINK_DIR=$PDIR \
		PROGRESS=1 rsync_dir
}

deploy_files_restore() { # BACKUP_DIR DST_MACHINE DST_DB
	local BACKUP_DIR=$1 DST_MACHINE=$2 DST_DB=$3
	checkvars BACKUP_DIR DST_MACHINE DST_DEPLOY
	checkdir $BACKUP_DIR
	machine_of "$DST_MACHINE"; local DST_MACHINE=$R1
	SRC_MACHINE= \
		SRC_DIR=$BACKUP_DIR/./. \
		DST_DIR=/home/$DST_DEPLOY \
		DST_USER=$DST_DEPLOY \
		PROGRESS=1 rsync_dir
}

deploy_backup_mysql() {
	deploy_mysql_backup $BACKUP_DIR/db.qp
}

deploy_restore_mysql() {
	deploy_mysql_restore $BSCKUP_DIR/db.qp $DST_MACHINE $DST_DEPLOY
}

deploy_backup_app() {
	deploy_files_backup $BACKUP_DIR/files $PREV_BACKUP_DIR
}

deploy_restore_app() {
	deploy_files_restore $BACKUP_DIR/files $DST_MACHINE $DST_DEPLOY
}

md_backup() { # MACHINE=|DEPLOY= [all|MODULE1 ...]
	local MD=${DEPLOY:-$MACHINE}
	checkvars MD
	backup_date; local DATE=$R1
	local BACKUP_DIR=backups/$MD/$DATE
	local PREV_BACKUP_DIR=backups/$MD/latest
	_md_backup "$@"; [[ $? == 2 ]] && { R1=; return 2; }
	ln_file $DATE backups/$MD/latest
	R1=$DATE
}

md_restore() { # MACHINE=|DEPLOY= DATE= [DST_MACHINE=|DST_DEPLOY=]
	local MD=${DEPLOY:-$MACHINE}
	local DST_MD=${DST_DEPLOY:-$DST_MACHINE}
	DST_MD=${DST_MD:-$MD}
	local DATE=$DATE
	if [[ $DATE == latest ]]; then
		DATE=`readlink backups/$MD/latest` \
			|| die "No latest backup for '$MD'"
	fi
	checkvars MD DST_MD DATE
	[[ $DST_DEPLOY ]] && machine_of "$DST_DEPLOY"; local DST_MACHINE=$R1
	local BACKUP_DIR=backups/$MD/$DATE
	MACHINE=$DST_MACHINE DEPLOY=$DST_DEPLOY md_stop all
	_md_restore
	MACHINE=$DST_MACHINE DEPLOY=$DST_DEPLOY md_start all
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
