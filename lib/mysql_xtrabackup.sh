# mysql xtrabackup backups, see:
#  https://www.percona.com/doc/percona-xtrabackup/8.0/xtrabackup_bin/incremental_backups.html
#  https://www.percona.com/doc/percona-xtrabackup/8.0/backup_scenarios/incremental_backup.html

xbkp() {
	must xtrabackup --user=root "$@" # password is read from ~/.my.cnf
}

mysql_backup_all() { # BKP_DIR [PARENT_BKP_DIR]
	local BKP_DIR="$1"
	local PARENT_BKP_DIR="$2"
	checkvars BKP_DIR

	must mkdir -p $BKP_DIR

	xbkp --backup --target-dir=$BKP_DIR \
		--rsync --parallel=$(nproc) --compress --compress-threads=$(nproc) \
		${PARENT_BKP_DIR:+--incremental-basedir=$PARENT_BKP_DIR}

	[ "$PARENT_BKP_DIR" ] && \
		must ln -s $PARENT_BKP_DIR $BKP_DIR-parent
}

mysql_restore_all() { # BKP_DIR

	local BKP_DIR="$1"
	checkvars BKP_DIR

	# walk up the parent chain and collect dirs in reverse.
	# BKP_DIR becomes the last parent, i.e. the non-incremental backup.
	local BKP_DIRS="$BKP_DIR"
	while true; do
		local PARENT_BKP_DIR="$(readlink $BKP_DIR-parent)"
		[ "$PARENT_BKP_DIR" ] || break
		BKP_DIRS="$PARENT_BKP_DIR $DIRS"
		BKP_DIR="$PARENT_BKP_DIR"
	done

	local RESTORE_DIR=/opt/mm-machine-restore/mysql

	# prepare base backup and all incrementals in order without doing rollbacks.
	sync_dir "$BKP_DIR" "$RESTORE_DIR"
	local PARENT_BKP_DIR=""
	for BKP_DIR in $BKP_DIRS; do
		xbkp --prepare --target-dir=$RESTORE_DIR --apply-log-only \
			--rsync --parallel=$(nproc) --decompress --decompress-threads=$(nproc) $O \
			${PARENT_BKP_DIR:+--incremental-dir=$BKP_DIR}
		PARENT_BKP_DIR=$BKP_DIR
	done

	# perform rollbacks.
	xbkp --prepare --target-dir=$RESTORE_DIR

	mysql_stop

	rm_dir /var/lib/mysql
	must mkdir -p /var/lib/mysql
	xbkp --move-back --target-dir=$RESTORE_DIR
	must chown -R mysql:mysql /var/lib/mysql
	rm_dir $RESTORE_DIR

	mysql_start

}

