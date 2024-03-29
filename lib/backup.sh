#use mysql fs

bkp_dir() { # machine|deploy [BKP] [files|mysql]
	[ "$1" ] || die
	[ "$2" ] || return
	echo -n "/root/mm-$1-backups/$2${3:+/$3}"
}

# print dir size in bytes excluding files that have more than one hard-link.
dir_lean_size() { # DIR
	local s="$(find $1 -type f -links 1 -printf "%s\n" | awk '{s=s+$1} END {print s}')"
	[ "$s" ] || s=0
	echo "$s"
}

deploy_backup_files() { # DEPLOY BACKUP_DIR [PARENT_BACKUP_DIR]
	local deploy="$1"
	local dir="$2"
	local parent_dir="$3"
	checkvars deploy dir

	sync_dir /home/$deploy $dir "$parent_dir"
}

deploy_restore_files() { # DEPLOY BACKUP_DIR
	local deploy="$1"
	local dir="$2"
	checkvars deploy dir

	sync_dir $dir /home/$deploy
	must chown -R $deploy:$deploy /home/$deploy
}

machine_backup_files() { # BACKUP_DIR [PARENT_BACKUP_DIR]
	local dir="$1"
	local parent_dir="$2"
	checkvars dir

	sync_dir /home $dir/home "$parent_dir"
	sync_dir /root/.acme.sh/ $dir "$parent_dir"

}

machine_restore_files() { # BKP_DIR
	local dir="$1"
	checkvars dir

	sync_dir $dir /home

	ls -1 $dir | while read $user; do
		user_create    $user
		user_lock_pass $user
		must chown -R $user:$user /home/$user
	done
}

_backup_info() { # TYPE BKP
	local dir=$(bkp_dir $1 $2)
	dir_lean_size $dir   # print dir lean size
	sha_dir       $dir   # print dir sha checksum
}
machine_backup_info() { _backup_info machine "$1"; }
deploy_backup_info()  { _backup_info deploy  "$1"; }

machine_backup() { # MBK [PARENT_MBK]
	local mbk="$1"
	local parent_mbk="$2"
	checkvars mbk

	mysql_backup_all     $(bkp_dir machine $mbk mysql) $(bkp_dir machine "$parent_mbk" mysql)
	machine_backup_files $(bkp_dir machine $mbk files) $(bkp_dir machine "$parent_mbk" files)

	machine_backup_info $mbk
}

machine_backup_remove() {
	local mbk="$1"
	checkvars mbk

	rm_dir $(bkp_dir machine $mbk)
}

machine_backup_copy() { # MBK [PARENT_MBK]
	local mbk="$1"
	local parent_mbk="$2"
	checkvars mbk

	SRC_DIR=$(bkp_dir machine $mbk) \
	LINK_DIR=$(bkp_dir machine $parent_mbk) \
		rsync_dir
}

machine_restore() { # MBK
	local mbk="$1"
	checkvars mbk

	deploy_stop_all

	mysql_restore_all     $(bkp_dir machine $mbk mysql)
	machine_restore_files $(bkp_dir machine $mbk files)

	deploy_start_all
}

deploy_backup() { # DEPLOY DBK [PARENT_DBK]
	local deploy="$1"
	local dbk="$2"
	local parent_dbk="$3"
	checkvars deploy dbk

	mysql_backup_db     $deploy $(bkp_dir deploy $dbk mysql)
	deploy_backup_files $deploy $(bkp_dir deploy $dbk files) $(bkp_dir deploy "$parent_dbk" files)

	deploy_backup_info $dbk
}

deploy_backup_remove() { # DBK
	local dbk="$1"
	checkvars dbk

	rm_dir $(bkp_dir deploy $dbk)
}

deploy_backup_copy() { # DBK [PARENT_DBK]
	local dbk="$1"
	local parent_dbk="$2"
	checkvars dbk

	SRC_DIR=$(bkp_dir deploy $dbk) \
	LINK_DIR=$(bkp_dir deploy $parent_dbk) \
		rsync_dir
}

deploy_restore() { # DBK
	local dbk="$1"
	checkvars dbk

	say "Restoring deploy from backup $dbk to $DEPLOY ... "
	checkvars DEPLOY APP MYSQL_PASS SECRET

	user_create    $DEPLOY
	user_lock_pass $DEPLOY

	mysql_restore_db     $DEPLOY $(bkp_dir deploy $dbk mysql)
	deploy_restore_files $DEPLOY $(bkp_dir deploy $dbk files)

	mysql_gen_my_cnf localhost $DEPLOY $MYSQL_PASS $DEPLOY
	deploy_gen_conf

	say "Deploy restored."
}
