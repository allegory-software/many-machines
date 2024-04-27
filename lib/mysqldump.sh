# mysqldump backups

mysql_backup_db() { # DB BACKUP_DIR
	local db="$1"
	local dir="$2"
	checkvars db dir
	must mkdir -p "$dir"
	say -n "mysqldump'ing $db to $dir ... "

	must mysqldump -u root \
		--no-create-db \
		--extended-insert \
		--order-by-primary \
		--triggers \
		--routines \
		--skip_add_locks \
		--skip-lock-tables \
		--quick \
		"$db" | qpress -i dump.sql "$dir/dump.qp"

	say "OK. $(stat --printf="%s" "$dir/dump.qp" | numfmt --to=iec) bytes written."
}

# rename user in DEFINER clauses in a mysqldump, in order to be able to
# restore the dump into a different db name.
# NOTE: All clauses containing **any user** are renamed!
mysqldump_fix_user() { # USER
	local user="$1"
	checkvars user
	sed "s/\`[^\`]*\`@\`localhost\`/\`$user\`@\`localhost\`/g"
}

mysql_restore_db() { # DB BACKUP_DIR
	local db="$1"
	local dir="$2"
	checkvars db dir

	mysql_drop_db   $db
	mysql_create_db $db
	(
		set -o pipefail
		must qpress -do "$dir/dump.qp" | mysqldump_fix_user $db | must mysql $db
	) || exit $?

	mysql_create_user   localhost $db localhost $db
	mysql_grant_user_db localhost $db $db
}
