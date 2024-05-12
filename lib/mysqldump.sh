# mysqldump backups

mysql_backup_db() { # DB [FILE]
	local db=$1 file=$2
	checkvars db
	[[ $file ]] && checkvars file
	[[ $file ]] && must mkdir -p $(dirname $file)
	sayn "Dumping MySQL database '$MACHINE:$db' "
	[[ $file ]] && sayn "to file '$file' ... " || sayn "to stdout ... "

	local qp_opt="-i db.sql $file"; [[ ! $file ]] && qp_opt="-io db.sql $file"
	must dry mysqldump -u root \
		--no-create-db \
		--extended-insert \
		--order-by-primary \
		--triggers \
		--routines \
		--skip_add_locks \
		--skip-lock-tables \
		--quick \
		$db | must qpress $qp_opt

	[[ $file ]] && say "OK. $(stat --printf=%s $file | numfmt --to=iec) written." || say "OK."
}

# rename user in DEFINER clauses in a mysqldump, in order to be able to
# restore the dump into a different db name.
# NOTE: All clauses containing **any user** are renamed!
mysqldump_fix_user() { # USER
	local user=$1
	checkvars user
	sed "s/\`[^\`]*\`@\`localhost\`/\`$user\`@\`localhost\`/g"
}

mysql_restore_db() { # DB FILE
	local db=$1 file=$2
	checkvars db file

	mysql_drop_db   $db
	mysql_create_db $db
	sayn "Restoring MySQL database '$MACHINE:$db' from file '$file' ... "
	must qpress -do $file | mysqldump_fix_user $db | must mysql $db
	say OK
}
