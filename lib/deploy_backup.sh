# deploy backup & restore

backup_date() {
	R1=`date -u +%Y-%m-%d-%H-%M-%S`
}

parse_backup_date() { # FILE -> TIME
	local s=${1%.*} # remove extension
	s=${s: -19} # keep date-time part
	local d=${s:0:10} # date part
	local t=${s:11} # time part
	t=${t//-/:}
	R1=`date -d "$d $t" +%s`
}

rel_backup_date() { # FILE
	parse_backup_date "$1"
	timeago $R1
}

list_deploy_db_backups() {
	local FMT="%-10s %-20s %s\n"
	printf "$FMT" DEPLOY AGE BACKUP_FILE
	for f in `ls -r backups`; do
		[[ -L backups/$f ]] && continue
		[[ ! -f backups/$f ]] && continue
		rel_backup_date "$f"; local d=$R1
		local s=${f%.*} # remove extension
		s=${s::-20} # remove date-time part
		printf "$FMT" "$s" "$d" "$f"
	done
}

list_deploy_files_backups() {
	local FMT="%-10s %-20s %s\n"
	printf "$FMT" DEPLOY AGE BACKUP_FILE
	for f in `ls -r backups`; do
		[[ -L backups/$f ]] && continue
		[[ ! -d backups/$f ]] && continue
		rel_backup_date "$f"; local d=$R1
		local s=${f::-20} # remove date-time part
		printf "$FMT" "$s" "$d" "$f"
	done
}

deploy_db_backup() {
	checkvars MACHINE DEPLOY
	backup_date; local DATE=$R1
	ssh_script "mysql_backup_db $DEPLOY tmp/$DEPLOY-$DATE.qp"
	SRC_MACHINE=$MACHINE DST_MACHINE= \
		SRC_DIR=/opt/mm/tmp/./$DEPLOY-$DATE.qp \
		DST_DIR=/opt/mm/backups/$DEPLOY-$DATE.qp \
		PROGRESS=1 MOVE=1 rsync_dir
	ln_file backups/$DEPLOY-$DATE.qp $DEPLOY-latest.qp
}

deploy_db_restore() {
	checkvars BACKUP DST_MACHINE DST_DB
	checkfile backups/$BACKUP

	SRC_MACHINE= \
		SRC_DIR=/opt/mm/backups/./$BACKUP \
		DST_DIR=/opt/mm/tmp/$DST_DB.$$.qp \
		PROGRESS=1 rsync_dir

	MACHINE=$DST_MACHINE ssh_script "
		mysql_restore_db $DST_DB tmp/$DST_DB.$$.qp
		must rm tmp/$DST_DB.$$.qp
	"
}

deploy_files_backup() {
	checkvars MACHINE
	backup_date; local DATE=$R1
	varfile var/deploys/$DEPLOY backup_files; local backup_files_file=$R1
	FILE_LIST_FILE=$backup_files_file SRC_MACHINE=$MACHINE DST_MACHINE= \
		SRC_DIR=/home/$DEPLOY \
		DST_DIR=/opt/mm/backups/$DEPLOY-$DATE \
		LINK_DIR=/opt/mm/backups/$DEPLOY-latest \
		PROGRESS=1 rsync_dir
	ln_file $DEPLOY-$DATE backups/$DEPLOY-latest
}

deploy_files_restore() {
	checkvars BACKUP DST_MACHINE DST_DEPLOY
	checkdir backups/$BACKUP

	MACHINE=$DST_MACHINE ssh_script "[[ -d /home/$DST_DEPLOY/.bashrc ]]" \
		|| die "Home dir for user '$DST_DEPLOY' is not populated. Create the user first."

	SRC_MACHINE= \
		SRC_DIR=/opt/mm/backups/$BACKUP/./. \
		DST_DIR=/home/$DST_DEPLOY \
		DST_USER=$DST_DEPLOY
		PROGRESS=1 rsync_dir
}
