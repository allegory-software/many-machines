# mysql lib: mysql wrapper for install, admin and querying.
# query works without prompt on both a root shell and a $DEPLOY user shell.

# mysql install --------------------------------------------------------------

has_mysql() { which mysql >/dev/null; }

version_mysql() {
	has_mysql && mysql --version | awk '{print $3}'
}

# mysql admin ----------------------------------------------------------------

mysql_config() { # NAME CONFIG
	local name="$1"
	local s="$2"
	checkvars name
	save "[mysqld]
$s" /etc/mysql/mysql.conf.d/mm-$name.cnf
}

# TODO: install percona's monitoring and management tool and see if it's
# worth having it running.
mysql_set_pool_size() {
	query "set global innodb_buffer_pool_size = $1"
}

# mysql password -------------------------------------------------------------

mysql_my_cnf() {
	local USER="$1"
	checkvars USER
	local HOME="/home/$USER"
	[ "$USER" == root ] && HOME=/root
	echo "$HOME/.my.cnf"
}

mysql_pass() { # USER/DB
	local cnf=$(mysql_my_cnf "$1")
	[ -f "$cnf" ] && sed -n 's/password=\(.*\)/\1/p' $cnf
}

mysql_pass_gen() { # FILE [ONCE]
	local FILE="$1"
	checkvars FILE
	[[ $2 && -f $FILE ]] && return 0
	local PASS; PASS=$(must openssl rand 23 | base64) || return # result is 32 chars
	save "$PASS" $FILE
}

mysql_pass_gen_once() { # FILE
	mysql_pass_gen "$1" once
}

# update ~/.my.cnf for using mysql and mysqldump without a password.
mysql_gen_my_cnf() { # HOST USER PASS [DB]
	local host="$1"
	local user="$2"
	local pass="$3"
	local db="$4"
	checkvars host user pass
	local cnf=$(mysql_my_cnf $user)
	checkvars cnf
	save "\
[client]
host=$host
user=$user
password=$pass
protocol=TCP
${db:+database=$db}
" $cnf $user
}

# mysql queries --------------------------------------------------------------

MYSQL_OPTS_SCRIPT="-N -B"
MYSQL_OPTS_PRETTY="-G -t"
_must_mysql() {
	local opts="$MYSQL_OPTS"
	[ "$MYSQL_PRETTY" ] && opts+=" $MYSQL_OPTS_PRETTY"
	[ "$opts" ] || opts="$MYSQL_OPTS_SCRIPT"
	if [ -f $HOME/.my.cnf ]; then
		must mysql $opts "$@"
	else
		# on a fresh mysql install we can login from the `root` system user
		# as mysql user `root` without a password because the default auth
		# plugin for `root` (without hostname!) is `unix_socket`.
		must mysql $opts -u root "$@"
	fi
}

query_on() { # DB SQL
	_must_mysql "$1" -e "$2"
}

query() { # SQL
	_must_mysql -e "$1"
}

mysql_exec_on() { # DB SQL
	[ "$DRY" ] && { echo "DRY mysql_exec_on $1 [[$2]]"; return; }
	query_on "$@"
}

mysql_exec() { # SQL
	[ "$DRY" ] && { echo "DRY mysql_exec [[$1]]"; return; }
	query "$1"
}

_mysql_create_or_alter_user() { # create|alter HOST USER PASS
	local create="$1"
	local host="$2"
	local user="$3"
	local pass="$4"
	checkvars create- host user pass
	mysql_exec "
		$create '$user'@'$host' identified with mysql_native_password by '$pass';
		flush privileges;
	"
}

mysql_create_user() { # HOST USER PASS
	say -n "Creating MySQL user $2@$1 ... "
	_mysql_create_or_alter_user "create user if not exists" "$@"
	say OK
}

mysql_update_pass() { # HOST USER PASS
	say -n "Updating password for MySQL user $2@$1 ... "
	_mysql_create_or_alter_user "alter user" "$@"
	say OK
}

mysql_drop_user() { # HOST USER
	local host="$1"
	local user="$2"
	checkvars host user
	say -n "Dropping MySQL user $user@$host ... "
	mysql_exec "drop user if exists '$user'@'$host'; flush privileges;"
	say OK
}

mysql_create_db() { # DB
	local db="$1"
	checkvars db
	say -n "Creating MySQL database $db ... "
	mysql_exec "
		create database if not exists \`$db\`
			character set utf8mb4
			collate utf8mb4_unicode_ci;
	"
	say OK
}

mysql_drop_db() { # DB
	local db="$1"
	checkvars db
	say -n "Dropping MySQL database $db ... "
	mysql_exec "drop database if exists \`$db\`"
	say OK
}

mysql_grant_user_db() { # HOST USER DB
	local host="$1"
	local user="$2"
	local db="$3"
	checkvars host user db
	say -n "Granting all rights on MySQL database $db to user $user ... "
	mysql_exec "
		grant all privileges on \`$db\`.* to '$user'@'$host';
		flush privileges;
	"
	say OK
}

mysql_rename_user() { # OLD_HOST OLD_USER NEW_HOST NEW_USER
	local old_host="$1"
	local old_user="$2"
	local new_host="$3"
	local new_user="$4"
	checkvars old_host old_user new_host new_user
	say -n "Renaming MySQL user $old_user to $new_user ... "
	mysql_exec "
		rename user '$old_user'@'$old_host' to '$new_user'@'$new_host';
		flush privileges;
	"
	say OK
}

mysql_dump_views() { # DB
	local db="$1"
	checkvars db
	local table
	local ignore="$(
		mysql_tables $db | while read -r table; do
			echo -n " --ignore-table=$db.$table"
		done
	)"
	must mysqldump --no-data --no-create-db --skip-opt $ignore $db
}

mysql_dump_triggers_procs_funcs() {
	local db="$1"
	checkvars db
	must mysqldump --triggers --routines \
		--no-create-info --no-data --no-create-db --skip-opt $db
}

mysql_move_tables() { # DB NEW_DB
	local db="$1"
	local new_db="$2"
	checkvars db new_db
	say -n "Moving all tables from $db to $new_db ... "
	local sql="$(query "
		select concat('RENAME TABLE \`', table_name, '\` TO \`$new_db\`.\`', table_name, '\`;') s
		from information_schema.tables
		where table_schema = '$db' and table_type = 'BASE TABLE'
		order by table_name
	")" || exit $?; mysql_exec_on $db "$sql"
	say OK
}

mysql_drop_views() { # DB
	local db="$1"
	checkvars db
	say -n "Dropping all views from $db ... "
	local sql="$(query "
		select concat('DROP VIEW \`', table_name, '\`;') s
		from information_schema.views
		where table_schema = '$db'
		order by table_name
	")" || exit $?; mysql_exec_on $db "$sql"
	say OK
}

mysql_drop_triggers() { # DB
	local db="$1"
	checkvars db
	say -n "Dropping all triggers from $db ... "
	local sql="$(query "
		select concat ('DROP TRIGGER \`', trigger_name, '\`;')
		from information_schema.triggers
		where trigger_schema = '$db';
	")" || exit $?; mysql_exec_on $db "$sql"
	say OK
}

mysql_drop_procs_funcs() { # DB
	local db="$1"
	checkvars db
	say -n "Dropping all procs & funcs from $db ... "
	local sql="$(query "
		select concat('DROP ', routine_type, ' \`', routine_name, '\`;') s
		from information_schema.routines
		where routine_schema = '$db'
	")" || exit $?; mysql_exec_on $db "$sql"
	say OK
}

# MySQL is missing a `RENAME DATABASE` command, so we have to do with
# its `RENAME TABLE` which can move tables between schemas along with
# their checks, indexes and foreign keys, but views, triggers, functions
# and procs we have to move (i.e. drop and recreate) ourselves.
#
# This function assumes there's a SQL user with the same name as the database
# that must also be renamed and granted access to the renamed database.
# Triggers and procs are created under that user in order to set their DEFINER.
#
mysql_rename_db() { # OLD_DB NEW_DB
	local db0="$1"
	local db1="$2"
	checkvars db0 db1

	mysql_create_db $db1

	local vtpf_sql="$(
		mysql_dump_views $db0
		mysql_dump_triggers_procs_funcs $db0
	)" || exit $?

	mysql_drop_views       $db0
	mysql_drop_triggers    $db0
	mysql_drop_procs_funcs $db0

	mysql_move_tables $db0 $db1

	mysql_rename_user   localhost $db0 localhost $db1
	mysql_grant_user_db localhost $db1 $db1

	# rename user in DEFINER clauses.
	vtpf_sql="$(echo "$vtpf_sql" | mysqldump_fix_user $db1)"

	say -n "Adding all views, triggers, procs & funcs from $db0 to $db1 ... "
	mysql_exec_on $db1 "$vtpf_sql"
	say OK

	mysql_drop_db $db0
}
