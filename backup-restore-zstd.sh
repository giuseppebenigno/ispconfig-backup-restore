#!/bin/bash
set -o pipefail
set -u
version="0.26.2"
# CHANGELOG: see CHANGELOG.md
#
# Copyright (c) Giuseppe Benigno <giuseppe.benigno@gmail.com>
#
# DESCRIPTION: see README.md

###############################
### Begin variables section ###
###############################

# Change the variables below to fit your computer/backup
# What parts of the system to backup. (yes/no)
BACKUP_DB="yes"
BACKUP_WEB="yes"
BACKUP_MAIL="yes"
BACKUP_SYSTEM="yes"
BACKUP_ROOT_DIR="/var/backup-restore"			# base directory for backups
COMPUTER=$(hostname -f)					# name of this computer
BACKUP_DIR="${BACKUP_ROOT_DIR}/${COMPUTER}"	# where to store the backups

VAR_DIR="/var"
WWW_DIR="www"							# Directory holding websites (global) (must reside in VAR_DIR!)
CLIENTS_DIR="clients"					# Directory holding websites per client (must reside in WWW_DIR!)
MAIL_DIR="vmail"						# Directory holding mail (must reside in VAR_DIR!)

DB_USER=$(cat /usr/local/ispconfig/server/lib/mysql_clientdb.conf | grep '$clientdb_user' | cut -d"'" -f 2)					# database user
DB_PASSWORD=$(cat /usr/local/ispconfig/server/lib/mysql_clientdb.conf | grep '$clientdb_password' | cut -d"'" -f 2)				# database password
EMAIL_FROM="$(hostname)@$(hostname -d)"
EMAIL_TO=root		# mail for the responsible person
TAR=$(which tar)						# name and location of tar
MAIL_BIN=$(which mail)					# name and location of mail

# --- COMPRESSION CONFIGURATION ---
# Calculate threads: 2/3 of available cores
TOTAL_CORES=$(nproc)
THREADS=$(( TOTAL_CORES * 2 / 3 ))
if [ "$THREADS" -lt 1 ]; then THREADS=1; fi

COMPRESSION_TOOL="zstd"
COMPRESSION_EXT=".tar.zst"
COMPRESS_ARGS="-T$THREADS" # Used when COMPRESSION_TOOL is part of a pipe
# --- END COMPRESSION CONFIGURATION ---










# --- SPLIT CONFIGURATION ---
# If set, backup files will be split into parts of this size.
# Example: SPLIT_SIZE="1G" or SPLIT_SIZE="500M"
# If empty, no splitting will occur.
SPLIT_SIZE="1G"
# --- END SPLIT CONFIGURATION ---

EXTRACT_ARGS="-xpf"					# tar extract arguments
TMP_DIR="/var/tmp/backup-restore"		# temp dir for database dump and other stuff
mkdir -p "$TMP_DIR"
DELETE_OLD="yes"						# Enable delete of files if free space < than $MIN_FREE_SPACE_GB (yes or anything else)
MIN_FREE_SPACE_GB="100"			# Minimum free space in GB before start of delete
LAST_MINUTE_OF_THE_DAY="2359"			# last minute of the day = last minute of the restored backup of the day restored

EXCLUDED="
	*.lck
	*.lock
	*.pid
	*.sock
	**/tmp/*
	/var/adm
	/var/amavis
	/var/cache
	/var/crash
	/var/lib/amavis
	/var/lib/apache2/fcgid
	/var/lib/mysql
	/var/lock
	/var/log/verlihub
	/var/run
	/var/spool/postfix/p*
	/var/spool/postfix/var
	/var/spool/postfix/dev/log
	/var/tmp
	/var/www/owncloud
	/var/www/roundcube
	/var/www/seafile
	/var/www/clients/client2/web44"			# exclude those dir's and files
REBOOT_ON_FINISH=false				# Reboot system after backup

# Services to stop before reboot (space separated list or array)
# IMPORTANT: The services will be stopped exactly in the order they are listed here.
# For example, if you use a process monitor like 'monit', it MUST be the first
# service to be stopped. Otherwise, it might restart services (like apache)
# immediately after the script stops them.
SERVICES_TO_STOP=(
	monit gogs seafile cron munin bind9 dovecot postfix
	apache2 mysqld certbot.timer clamav-daemon
	clamav-freshclam spamassassin fail2ban
)

###################################
### End user editable variables ###
###################################

#########################################################
# You should NOT have to change anything below here     #
#########################################################

# --- PRE-FLIGHT CHECKS & SETUP ---
# Pre-flight check: tools
check_tools() {
	local tools=("tar" "mysqldump" "mysql" "mysqlcheck" "hostname" "nproc" "df" "awk" "cut" "basename" "mkdir" "rm" "sha256sum" "dirname")
	if [ -n "${SPLIT_SIZE:-}" ]; then tools+=("split"); fi
	tools+=("$COMPRESSION_TOOL")
	
	for tool in "${tools[@]}"; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			echo "Error: Required tool '$tool' not found."
			exit 1
		fi
	done
}
check_tools

# Global Date Variables
MONTH_DATE=$(date +%Y-%m)					# Date, YYYY-MM, eg. 2009-09
DAY_OF_MONTH=$(date +%d)					# Date of the Month, DD, eg. 27
FULL_DATE="${MONTH_DATE}-${DAY_OF_MONTH}"	# Full Date, YYYY-MM-DD, year sorted, eg. 2009-11-21

# Cleanup on exit
cleanup() {
	local exit_code=$?
	# Clean up temporary files if they exist
	if [ -d "$TMP_DIR" ]; then
		rm -f "$TMP_DIR/db-"*"-${FULL_DATE}.sql"
		rm -f "$TMP_DIR/maildata"
		rm -f "$TMP_DIR/excluded"
		rm -f "$TMP_DIR/full-backup"*".lck"
		# Remove TMP_DIR only if it's empty
		rmdir "$TMP_DIR" 2>/dev/null
	fi
	exit $exit_code
}
trap cleanup EXIT ERR SIGINT SIGTERM
# --- END PRE-FLIGHT CHECKS ---

# Enable globbing for hidden files (dotglob) and handle empty matches (nullglob)
shopt -s dotglob nullglob

SYSTEM_DIRECTORIES=("/etc")
WEB_DIRECTORIES=()
MAIL_DIRECTORIES=()

# Function to check if a path is excluded
is_excluded() {
	local path="$1"
	for pattern in $EXCLUDED; do
		# Use shell glob matching for the pattern
		if [[ "$path" == $pattern ]]; then
			return 0
		fi
	done
	return 1
}

# Add /var excluding subdirectories /var/www and /var/vmail to SYSTEM_DIRECTORIES
# Also exclude the BACKUP_ROOT_DIR itself
if [[ -d "$VAR_DIR" ]]; then
	for path in "$VAR_DIR"/*; do
		i=$(basename "$path")
		if [[ "$path" != "$BACKUP_ROOT_DIR" && "$i" != "$WWW_DIR" && "$i" != "$MAIL_DIR" ]]; then
			if is_excluded "$path"; then continue; fi
			SYSTEM_DIRECTORIES+=("$path")
		fi
	done
fi

# Add /var/www excluding subdirectories of /var/www/clients and all subdirectories of /var/www/clients to WEB_DIRECTORIES
if [[ -d "$VAR_DIR/$WWW_DIR" ]]; then
	for path in "$VAR_DIR/$WWW_DIR"/*; do
		i=$(basename "$path")
		if [[ "$i" != "$CLIENTS_DIR" ]]; then
			if is_excluded "$path"; then continue; fi
			WEB_DIRECTORIES+=("$path")
		fi
	done

	if [[ -d "$VAR_DIR/$WWW_DIR/$CLIENTS_DIR" ]]; then
		for client_path in "$VAR_DIR/$WWW_DIR/$CLIENTS_DIR"/*; do
			# If it's a directory, add its children (websites)
			if [[ -d "$client_path" ]]; then
				for web_path in "$client_path"/*; do
					if is_excluded "$web_path"; then continue; fi
					WEB_DIRECTORIES+=("$web_path")
				done
			else
				# If it's a file, adds it directly
				if is_excluded "$client_path"; then continue; fi
				WEB_DIRECTORIES+=("$client_path")
			fi
		done
	fi
fi

# Add all subdirectories of MAIL_DIR to MAIL_DIRECTORIES
if [[ -d "$VAR_DIR/$MAIL_DIR" ]]; then
	for path in "$VAR_DIR/$MAIL_DIR"/*; do
		if is_excluded "$path"; then continue; fi
		MAIL_DIRECTORIES+=("$path")
	done
fi

shopt -u dotglob nullglob

me=$(basename "$0")
headline="
---------------------=== The backup-restore-zstd script by Giuseppe Benigno <giuseppe.benigno@gmail.com> ===---------------------
"
print_usage() {
	echo "$headline"
	cat <<EOF
The backup part requires some configuration in the header of the script
and it's supposed to be run from cron.
The restore part it's supposed to be run from command line.
backup part Usage:
\t $me
\t $me -o|--only [db,web,mail,system,all]

restore part Usage:
\t $me [type-of-restore] [dir|db] [YYYY-MM-DD] [path]

\t $me dir [dir-to-restore] [to-date] [path]
\t $me dir all [to-date] [path]
\t $me db [db-to-restore] [to-date]
\t $me db all [to-date]

Where 'dir' or 'db' to restore is one of the configured dirs or db's to
backup, or 'all' to restore all dirs or db's.
Date format is full date, year sorted, YYYY-MM-DD, like 2009-01-30.
'path' is for dirs and is the path on which you want to extract the backup.
If the path to extract is not set, then the backup is extracted on /.
For more info read the header of this script!
-===--===--===--===--===--===--===--===--===--===--===--===--===--===--===--===-
EOF
}

backup () {
	if [ "${1:-}" == "-o" ] || [ "${1:-}" == "--only" ]; then
		if [ -z "${2:-}" ]; then
			echo "Error: -o|--only requires an argument (db,web,mail,system,all)"
			print_usage
			exit 1
		fi

		# Disable all by default when --only is used
		BACKUP_DB="no"
		BACKUP_WEB="no"
		BACKUP_MAIL="no"
		BACKUP_SYSTEM="no"

		IFS=',' read -ra ADDR <<< "$2"
		for component in "${ADDR[@]}"; do
			case "$component" in
				db) BACKUP_DB="yes" ;;
				web) BACKUP_WEB="yes" ;;
				mail) BACKUP_MAIL="yes" ;;
				system) BACKUP_SYSTEM="yes" ;;
				all)
					BACKUP_DB="yes"
					BACKUP_WEB="yes"
					BACKUP_MAIL="yes"
					BACKUP_SYSTEM="yes"
					;;
				*)
					echo "Error: Invalid component '$component'"
					print_usage
					exit 1
					;;
			esac
		done
	elif [ -n "${1:-}" ]; then
		print_usage
		exit 1
	fi


	# Log file is now inside the monthly directory
	LOG_FILE=$BACKUP_DIR/$MONTH_DATE/log/backup-$FULL_DATE.log

	#################
	### Functions ###
	#################

	function log {
		NOW=$(date "+%Y-%m-%d %H:%M:%S")		# I like this type of date. Syslog type doesn't use the year.
		if [ -e "$LOG_FILE" ]; then
			echo "$NOW - $(basename $0) - $1" >> "$LOG_FILE"
			echo "$NOW - $(basename $0) - $1" >> "$TMP_DIR/maildata"
		else
			if [ ! -d "$BACKUP_DIR/$MONTH_DATE/log" ]; then
				mkdir -p "$BACKUP_DIR/$MONTH_DATE/log"
				if [ -n "${log1:-}" ]; then
					echo "${log1}" >> "$LOG_FILE"
					echo "${log1}" >> "$TMP_DIR/maildata"
				fi
				echo "$NOW - $(basename $0) - First run: monthly log dir and log file created." >> "$LOG_FILE"
				echo "$NOW - $(basename $0) - First run: monthly log dir and log file created." >> "$TMP_DIR/maildata"
			else
				echo "$NOW - $(basename $0) - Log file created." >> "$LOG_FILE"
				echo "$NOW - $(basename $0) - Log file created." >> "$TMP_DIR/maildata"
			fi
				echo "$NOW - $(basename $0) - $1" >> "$LOG_FILE"
				echo "$NOW - $(basename $0) - $1" >> "$TMP_DIR/maildata"
		fi
	}

	function check_mdir {
		log "Checking if month dirs exist: $BACKUP_DIR/$MONTH_DATE"
		mkdir -p "$BACKUP_DIR/$MONTH_DATE"/{db,web,mail,system,log}
		log "Month subdirs (db, web, mail, system, log) ensured"
	}

	function check_tempdir {
		log "Checking if temp dir exist: $TMP_DIR"
		if [ -d "$TMP_DIR" ]; then
			log "Temp dir $TMP_DIR exists"
		else
			mkdir -p "$TMP_DIR"
			log "Temp dir $TMP_DIR created"
		fi
	}

	function del_old_files {
		to_del=$(ls -ctF "$BACKUP_DIR" | tail -n 1 | sed 's/\///g') # sort files in ctime order and select the first modified
		#if [ -d "$BACKUP_DIR/$to_del" ]; then
		#    # recover db backups and store only the ones from de first day of month or from the first full backup of dirs
		#    # list all db backups in month dir, extract first date
		#    day=$(ls -ct "$BACKUP_DIR/$to_del" | tail -n 1 | cut -d "-" -f 5 | cut -d "." -f 1)
		#    # then list all db file names
		#    dblist=$(ls -ct "$BACKUP_DIR/$to_del" | grep "$to_del-$day")
		#    for db in $dblist; do
		#	 mv "$BACKUP_DIR/$to_del/$db" "$BACKUP_DIR/$db"	# moving files keeps creation date
		#    done
		#	log "Kept db's from $to_del-$day"
		#else
			rm -rf "$BACKUP_DIR/$to_del"
			log "Deleted old: $BACKUP_DIR/$to_del"
			count=0
			while [ $count -lt 3 ]; do
				count=$(($count+1))
				#echo $count argmax # for test
				check_space
			done
		#fi
	}

	function check_space {
		FREE_SPACE_KB=$(df -P -k "$BACKUP_DIR" | awk 'NR==2{print $4}')
		FREE_SPACE_GB=$(( FREE_SPACE_KB / 1024 / 1024 ))

		if [ "$FREE_SPACE_GB" -lt "$MIN_FREE_SPACE_GB" ];then
			log "There is only ${FREE_SPACE_GB}GB free space on $BACKUP_DIR"
			if [ "$DELETE_OLD" = "yes" ]; then
				del_old_files
			else
				log "No free space and DELETE_OLD=$DELETE_OLD so we abort here and send mail to $EMAIL_TO"
				if [ -n "${MAIL}" ]; then
					${MAIL} -s "Daily backup of $COMPUTER $(date +'%F')" -r "$EMAIL_FROM" "$EMAIL_TO" < "$TMP_DIR/maildata"
				fi
				exit
			fi
		else
			log "Free space ${FREE_SPACE_GB}GB on $BACKUP_DIR ok."
		fi
	}

	function generate_checksum {
		local target="$1"
		log "Generating SHA256 checksum for $target..."
		if [ -d "$target" ]; then
			# For directories (split backups), checksum all parts using relative paths
			(cd "$(dirname "$target")" && find "$(basename "$target")" -type f -exec sha256sum {} +) > "$target.sha256"
		elif [ -f "$target" ]; then
			(cd "$(dirname "$target")" && sha256sum "$(basename "$target")") > "$target.sha256"
		fi
	}

	function db_backup {
		#Replace / with _ in dir name => filename
		#DIR_NAME=$(echo "$DIRECTORIES" | awk '{gsub("/", "_", $0); print}')

		### All db's check and correct any errors found

		log "Starting automatic repair and optimize for all databases..."
		mysqlcheck -u$DB_USER -p$DB_PASSWORD --all-databases --optimize --auto-repair --silent 2>&1
		### Starting database dumps
		for i in $(mysql -u"$DB_USER" -p"$DB_PASSWORD" -Bse 'show databases' | grep -Ev "^(information_schema|performance_schema)$"); do
			# Target subfolder for this database
			B_DIR="$BACKUP_DIR/$MONTH_DATE/db/db-$i"
			
			# Check if backup already exists for today
			if [ -n "$SPLIT_SIZE" ]; then
				B_TARGET="$B_DIR/db-$i-$FULL_DATE"
				if [ -d "$B_TARGET" ]; then
					log "Database $i already backed up (split) for $FULL_DATE. Skipping."
					continue
				fi
			else
				B_TARGET="$B_DIR/db-$i-$FULL_DATE$COMPRESSION_EXT"
				if [ -f "$B_TARGET" ]; then
					log "Database $i already backed up for $FULL_DATE. Skipping."
					continue
				fi
			fi

			log "Starting mysqldump $i"
			mysqldump -u"$DB_USER" -p"$DB_PASSWORD" "$i" --allow-keywords --comments=false --routines --triggers --add-drop-table > "$TMP_DIR/db-$i-$FULL_DATE.sql"
			
			mkdir -p "$B_DIR"
			if [ -n "$SPLIT_SIZE" ]; then
				rm -rf "$B_TARGET.part"
				mkdir -p "$B_TARGET.part"
				# We pipe tar to split. Tar writes to stdout (-f -)
				if nice -n 19 "$TAR" -cpSP -f - -C "$TMP_DIR" "db-$i-$FULL_DATE.sql" | "$COMPRESSION_TOOL" $COMPRESS_ARGS | split -b "$SPLIT_SIZE" --additional-suffix="$COMPRESSION_EXT" - "$B_TARGET.part/part-"; then
					mv "$B_TARGET.part" "$B_TARGET"
					generate_checksum "$B_TARGET"
					log "Dump OK. $i database saved OK! (Split)"
				else
					log "Error splitting database backup for $i"
				fi
			else
				rm -f "$B_TARGET.part"
				if nice -n 19 "$TAR" -c -I "zstd -T$THREADS" -P -f "$B_TARGET.part" -C "$TMP_DIR" "db-$i-$FULL_DATE.sql"; then
					mv "$B_TARGET.part" "$B_TARGET"
					generate_checksum "$B_TARGET"
					log "Dump OK. $i database saved OK!"
				else
					log "Error backing up database $i"
				fi
			fi
			rm -rf "$TMP_DIR/db-$i-$FULL_DATE.sql"
		done
	}

	function dirs_backup {
		# This function now takes two arguments:
		# 1: target subfolder (e.g., web, mail, or system)
		# 2: name of the array containing directories to back up
		local subfolder="$1"
		local array_name="$2[@]"
		local targets=("${!array_name}")

		rm -rf "$TMP_DIR/excluded"
		touch "$TMP_DIR/excluded"
		for pattern in $EXCLUDED; do
			echo "$pattern" >> "$TMP_DIR/excluded"
		done

		for i in "${targets[@]}"; do
			UNDERSCORED_DIR=$(echo "$i" | awk '{gsub("/", "_", $0); print}')
			TARGET_DIR="$i"
			# Resource-specific subfolder within the monthly directory
			RES_DIR="$BACKUP_DIR/$MONTH_DATE/$subfolder/$UNDERSCORED_DIR"


			# Check for monthly full backup in the resource subfolder
			FULL_BACKUP_FILE=$(ls "$RES_DIR" 2>/dev/null | grep "^full-${MONTH_DATE}-")

			if [ -z "$FULL_BACKUP_FILE" ]; then
				# Monthly full backup
				log "No full backup found for $TARGET_DIR in this month. Full backup now!"
				echo > "$TMP_DIR/full-backup$UNDERSCORED_DIR.lck"
				echo "$TARGET_DIR"
				NEWER=""
				
				mkdir -p "$RES_DIR"
				if [ -n "$SPLIT_SIZE" ]; then
					BACKUP_DIR_NAME="$RES_DIR/full-$FULL_DATE"
					if [ ! -d "$BACKUP_DIR_NAME" ]; then
						rm -rf "$BACKUP_DIR_NAME.part"
						mkdir -p "$BACKUP_DIR_NAME.part"
						ionice -c3 nice -n 19 "$TAR" -cpSP $NEWER -f - -X "$TMP_DIR/excluded" "$TARGET_DIR" | "$COMPRESSION_TOOL" $COMPRESS_ARGS | split -b "$SPLIT_SIZE" --additional-suffix="$COMPRESSION_EXT" - "$BACKUP_DIR_NAME.part/part-"
						RET=$?
						if [ $RET -le 1 ]; then
							mv "$BACKUP_DIR_NAME.part" "$BACKUP_DIR_NAME"
							generate_checksum "$BACKUP_DIR_NAME"
							[ $RET -eq 1 ] && log "Full monthly backup of $TARGET_DIR done with non-fatal warnings (split to $subfolder)." || log "Full monthly backup of $TARGET_DIR done (split to $subfolder)."
						else
							log "Error backing up $TARGET_DIR (split) - Exit code: $RET"
						fi
					fi
				else
					BACKUP_FILE="$RES_DIR/full-$FULL_DATE$COMPRESSION_EXT"
					rm -f "$BACKUP_FILE.part"
	 
					if [ ! -f "$BACKUP_FILE" ]; then
						ionice -c3 nice -n 19 "$TAR" -cpSP $NEWER -f - -X "$TMP_DIR/excluded" "$TARGET_DIR" | "$COMPRESSION_TOOL" $COMPRESS_ARGS > "$BACKUP_FILE.part"
						RET=$?
						if [ $RET -le 1 ]; then
							mv "$BACKUP_FILE.part" "$BACKUP_FILE"
							generate_checksum "$BACKUP_FILE"
							[ $RET -eq 1 ] && log "Full monthly backup of $TARGET_DIR done with non-fatal warnings (to $subfolder)." || log "Full monthly backup of $TARGET_DIR done (to $subfolder)."
						else
							log "Error backing up $TARGET_DIR - Exit code: $RET"
						fi
					fi
				fi
			else
				# If there is already a full backup for this month, let's do the incremental backup
				if [ ! -e "$TMP_DIR/full-backup$UNDERSCORED_DIR.lck" ]; then
					log "Starting incremental backup for: $TARGET_DIR"
					echo "$TARGET_DIR"
					NEWER="--newer $FULL_DATE"
					mkdir -p "$RES_DIR"
					if [ -n "$SPLIT_SIZE" ]; then
						BACKUP_DIR_NAME="$RES_DIR/i-$FULL_DATE"
						if [ ! -d "$BACKUP_DIR_NAME" ]; then
							rm -rf "$BACKUP_DIR_NAME.part"
							mkdir -p "$BACKUP_DIR_NAME.part"
							ionice -c3 nice -n 19 "$TAR" -cpSP $NEWER -f - -X "$TMP_DIR/excluded" "$TARGET_DIR" | "$COMPRESSION_TOOL" $COMPRESS_ARGS | split -b "$SPLIT_SIZE" --additional-suffix="$COMPRESSION_EXT" - "$BACKUP_DIR_NAME.part/part-"
							RET=$?
							if [ $RET -le 1 ]; then
								mv "$BACKUP_DIR_NAME.part" "$BACKUP_DIR_NAME"
								generate_checksum "$BACKUP_DIR_NAME"
								[ $RET -eq 1 ] && log "Incremental backup for $TARGET_DIR done with non-fatal warnings (split to $subfolder)." || log "Incremental backup for $TARGET_DIR done (split to $subfolder)."
							else
								log "Error backing up $TARGET_DIR (split) - Exit code: $RET"
							fi
						fi
					else
						BACKUP_FILE="$RES_DIR/i-$FULL_DATE$COMPRESSION_EXT"
						rm -f "$BACKUP_FILE.part"
	 
						if [ ! -f "$BACKUP_FILE" ]; then
							ionice -c3 nice -n 19 "$TAR" -cpSP $NEWER -f - -X "$TMP_DIR/excluded" "$TARGET_DIR" | "$COMPRESSION_TOOL" $COMPRESS_ARGS > "$BACKUP_FILE.part"
							RET=$?
							if [ $RET -le 1 ]; then
								mv "$BACKUP_FILE.part" "$BACKUP_FILE"
								generate_checksum "$BACKUP_FILE"
								[ $RET -eq 1 ] && log "Incremental backup for $TARGET_DIR done with non-fatal warnings (to $subfolder)." || log "Incremental backup for $TARGET_DIR done (to $subfolder)."
							else
								log "Error backing up $TARGET_DIR - Exit code: $RET"
							fi
						fi
					fi
				else
					log "Lock file for $TARGET_DIR full backup exists!"
				fi
			fi

			# Clean full backup directory lock file
			rm -rf "$TMP_DIR/full-backup$UNDERSCORED_DIR.lck"
		done

		# Clean temp dir
		rm -rf "$TMP_DIR/excluded"
	}

	function reboot_system {
		log "Stopping services before reboot..."
		for service in "${SERVICES_TO_STOP[@]}"; do
			if systemctl is-active --quiet "$service"; then
				systemctl stop "$service"
				log "Service $service stopped."
			fi
		done

		shutdown -r now
		reboot
	}

	START=$(date +%s)
	if [ -n "${MAIL_BIN}" ]; then
		SUBJECT="Backup of $COMPUTER STARTED $(date +'%F')"
		echo "Backup started at $(date '+%Y-%m-%d %H:%M:%S')" | "$MAIL_BIN" -s "${SUBJECT}" -r "$EMAIL_FROM" "$EMAIL_TO"
	fi

	rm -f "$TMP_DIR/maildata"
	if [ -d "$BACKUP_DIR" ]; then
		check_space
	else
		mkdir -p "$BACKUP_DIR"
		log "$(basename $0) - First run: primary dir $BACKUP_DIR created."
	fi

	check_mdir
	check_tempdir
	log "Using script version $version with compression tool: $COMPRESSION_TOOL ($COMPRESSION_EXT)"
	[ x"${BACKUP_DB}" == "xyes" ] && db_backup
 
	# Determine which file categories to back up
	if [ x"${BACKUP_WEB}" == "xyes" ]; then
		log "Starting web backups (web/)..."
		dirs_backup "web" "WEB_DIRECTORIES"
	fi
 
	if [ x"${BACKUP_MAIL}" == "xyes" ]; then
		log "Starting mail backups (mail/)..."
		dirs_backup "mail" "MAIL_DIRECTORIES"
	fi
 
	if [ x"${BACKUP_SYSTEM}" == "xyes" ]; then
		log "Starting system backups (system/)..."
		dirs_backup "system" "SYSTEM_DIRECTORIES"
	fi

	# End of script
	log "All backup jobs done. Exiting script!"
	END=$(date +%s)
	RUN_TIME=$((END-START))
	# Convert seconds to HH:MM:SS
	FORMATTED_TIME=$(date -u -d @"${RUN_TIME}" +'%H:%M:%S')
	log "Run time: ${FORMATTED_TIME} (${RUN_TIME}s)"

	# Calculate sizes
	FULL_SIZE="0"
	# Search for full backups in the subfolders of the current month
	FULL_CHECK=$(du -ch "$BACKUP_DIR/$MONTH_DATE"/{web,system,mail}/full* 2>/dev/null | tail -n1 | awk '{print $1}')
	if [ -n "$FULL_CHECK" ]; then
		FULL_SIZE=$FULL_CHECK
	fi

	INCR_SIZE="0"
	if [ -d "$BACKUP_DIR/$MONTH_DATE" ]; then
		INCR_SIZE=$(du -sh "$BACKUP_DIR/$MONTH_DATE" | awk '{print $1}')
	fi

	# Get available space on the partition hosting BACKUP_ROOT_DIR
	AVAIL_SPACE=$(df -hP "$BACKUP_ROOT_DIR" | awk 'NR==2 {print $4}')

	log "Stats for $MONTH_DATE | Full: $FULL_SIZE | Incr/DB/Log: $INCR_SIZE | Free: $AVAIL_SPACE"

	if [ -n "${MAIL_BIN}" ]; then
		SUBJECT="Backup of $COMPUTER $(date +'%F')"
# 		MESSAGE="Hello"
# 		echo "${MESSAGE}" | mail -s "${SUBJECT}" "$EMAIL_FROM" "$EMAIL_TO"
		"$MAIL_BIN" -s "${SUBJECT}" -r "$EMAIL_FROM" "$EMAIL_TO" < "$TMP_DIR/maildata"
	else
		log "I can't send alert because I can't find mail software!"
	fi

	if [ "${REBOOT_ON_FINISH}" = "true" ]; then
		reboot_system
	fi
}

restore() {
	del_res() {
		# We now need to remove the newer files created after the restored backup date.
		# Strip leading slash from $2 for find to work with extracted absolute paths
		to_rem=$(find "$path/${2#/}" -newer "$TMP_DIR/dateend" 2>/dev/null)
		echo -en "\n$headline\n    For a clean backup restored at $3 we need now to delete the files\ncreated after the backup date.\n    If exists, a list of files to be deleted follows:\n\n"
		while IFS= read -r a; do
			echo -e "To be removed: $a"
		done <<< "$to_rem"

		echo -en "\nPlease input \"yes\" to delete those files, if they exist, and press [ENTER]: "
		read del
		if [[ "$del" = "yes" ]]; then
			while IFS= read -r a; do
				rm -rf "$a"
			done <<< "$to_rem"
			echo -en "All restore jobs done!\nDir $2 restored to date $3!\n"
			exit
		fi
	}

	if [ -z "$4" ]; then
		path="/"
	else
		path=$4					# this is the path where to extract the files
	fi
	mesaj=""
	dblist=""
	rdb=""

	RDATE=$3
	DAY_OF_MONTH=$(echo "$RDATE" | cut -d "-" -f3)		# Date of the Month eg. 27
	MONTH_DATE=$(echo "$RDATE" | cut -d "-" -f2)
	YDATE=$(echo "$RDATE" | cut -d "-" -f1)

	type=$1
	dir=$(echo "$2" | awk '{gsub("/", "_", $0); print}')

	if [ -z "$3" ]; then
		print_usage
		exit
	fi

	# poor date input verification: ${#RDATE} is 10 for a correct date 2009-01-30
	# find the first possible restore date=day
	# Updated to search in subdirectories
	first_backup=$(find "$BACKUP_DIR" -maxdepth 2 -name "full*-*" 2>/dev/null | sort | head -n 1)
	if [ -n "$first_backup" ]; then
		year=$(echo "$(basename "$first_backup")" | cut -d "-" -f 2)
		md=$(echo "$(basename "$first_backup")" | cut -d "-" -f 3)
		day=$(echo "$(basename "$first_backup")" | cut -d "-" -f 4 | cut -d "." -f 1)
		resdate=$year$md$day
	else
		# Fallback if no backup found
		resdate=$(date +%Y%m%d)
	fi

	dh="1234"
	err=$(touch -t $YDATE$MONTH_DATE$DAY_OF_MONTH$dh $TMP_DIR/datestart 2>&1)

	if [ -n "$err" ] & [ ${#RDATE} != 10 ]; then
		#echo "err = $err"
		print_usage
		echo -e "Invalid date format. Correct YYYY-MM-DD. Ex.: 2009-01-14\n"
		exit
	fi

	# check to see if user inputs date in future
	TD=$(date +%s) # today in epoch
	ID=$(date --date "$RDATE" +%s) # input date in epoch
	RD=$(date --date "$resdate" +%s) # first backup date in epoch

	if [ "$ID" -ge "$TD" ]; then
		print_usage
		echo -e "Invalid date format. Date supplied $RDATE is in the future!\n"
		exit
	fi

	if [ "$RD" -gt "$ID" ]; then
		print_usage
		echo -e "Invalid date format. Date supplied $RDATE is before the first backup on $year-$md-$day!\n"
		exit
	fi


	#echo "Checking if path dir exist: $path"
	if [ $type = "dir" ]; then
		# echo $dir and $path
		if [ -d $path ]; then
			if [ -n "$path" ]; then
				mesaj=""
			fi
		else
			mesaj="Extraction dir $path invalid"
			exit
		fi
	fi

	if [ "$type" = "db" ]; then
		DB_ROOT="$BACKUP_DIR/$YDATE-$MONTH_DATE/db"
		dblist=$(find "$DB_ROOT" -maxdepth 2 \( -type f -o -type d \) 2>/dev/null | grep "/db-" | grep $YDATE-$MONTH_DATE-$DAY_OF_MONTH | sed 's_.*/__' | cut -d "-" -f2 | sort -u)
	fi

	# We now prompt the user with the info entered on the comand line.
	# clear
	echo -en "\n    You want to restore $1 $2 to date $3.\n\nPlease input \"yes\" if the above is ok with you and press [ENTER]: "
	read ok

	if [[ "$ok" = "yes" ]]; then
		if [[ "$1" == "dir" ]]; then
			if [[ "$2" == "all" ]]; then
				echo -en "\nExtracting all dir's backup from date $3 to $path:\n"
				sleep 5 # We wait 5 secs for the user to see what's happening.
			else
				# We suppose the user uses /dir
				if [[ "${SYSTEM_DIRECTORIES[*]} ${WEB_DIRECTORIES[*]} ${MAIL_DIRECTORIES[*]} all" =~ "$2" ]]; then
					echo -en "\nTrying to restore $2 dir's backup from date $3 to $path:\n\n"
					# we say "trying" because if the requested dir is "al" it matches!
					sleep 5
				fi
			fi
		elif [[ "$1" == "db" ]]; then
			if [[ "$2" == "all" ]]; then
				echo -en "\nRestoring all mysql databases from date $3 to local server:\n"
				sleep 5
			else
				if [[ "$dblist" =~ "$2" ]]; then
					echo -en "\nTrying to restore $2 database backup from date $3 to local server:\n\n"
					# we say "trying" because it's an imperfect check, same as above
					sleep 5
				fi
			fi
		fi
	else
		echo -en "\nInvalid entry. Exiting script...\n\n"
		exit
	fi

	dst="010000" # first minute of the first day
	touch -t $YDATE$MONTH_DATE$dst $TMP_DIR/datestart 2>&1
	touch -t $YDATE$MONTH_DATE$DAY_OF_MONTH$LAST_MINUTE_OF_THE_DAY $TMP_DIR/dateend 2>&1
	if [ "$type" = "dir" ]; then
		if [[ "${SYSTEM_DIRECTORIES[*]} ${WEB_DIRECTORIES[*]} ${MAIL_DIRECTORIES[*]} all" =~ "$2" ]]; then
			# Search for requested directories in web, mail, and system subdirectories
			B_WEB="$BACKUP_DIR/$YDATE-$MONTH_DATE/web"
			B_MAIL="$BACKUP_DIR/$YDATE-$MONTH_DATE/mail"
			B_SYSTEM="$BACKUP_DIR/$YDATE-$MONTH_DATE/system"
			B_SEARCH_DIRS=()
			[ -d "$B_WEB" ] && B_SEARCH_DIRS+=("$B_WEB")
			[ -d "$B_MAIL" ] && B_SEARCH_DIRS+=("$B_MAIL")
			[ -d "$B_SYSTEM" ] && B_SEARCH_DIRS+=("$B_SYSTEM")

			if [ "$dir" = "all" ]; then
				farh=$(find "${B_SEARCH_DIRS[@]}" -maxdepth 2 \( -type f -o -type d \) -newer "$TMP_DIR/datestart" -a ! -newer "$TMP_DIR/dateend" 2>/dev/null | grep /full- | grep -v "\.sha256$")
				arh=$(find "${B_SEARCH_DIRS[@]}" -maxdepth 2 \( -type f -o -type d \) -newer "$TMP_DIR/datestart" -a ! -newer "$TMP_DIR/dateend" 2>/dev/null | grep -v "/full-" | grep -vE "/(db-|log/)" | grep -v "\.sha256$")
			else
				farh=$(find "${B_SEARCH_DIRS[@]}" -maxdepth 2 \( -type f -o -type d \) -newer "$TMP_DIR/datestart" -a ! -newer "$TMP_DIR/dateend" 2>/dev/null | grep "/$dir/" | grep /full- | grep -v "\.sha256$")
				arh=$(find "${B_SEARCH_DIRS[@]}" -maxdepth 2 \( -type f -o -type d \) -newer "$TMP_DIR/datestart" -a ! -newer "$TMP_DIR/dateend" 2>/dev/null | grep "/$dir/" | grep -v "/full-" | grep -vE "/(db-|log/)" | grep -v "\.sha256$")
			fi

			# Filter out entries that are not in the child level of our resource dirs (to avoid finding files inside parts folders if they weren't sed'd out)
			# But find with maxdepth 2 already handles this for the monthly root.
			
			for f_path in $farh; do
				f=$(basename "$f_path")
				echo -en "\tExtracting $f (from $(dirname "$f_path"))...\n\n"
				if [ -d "$f_path" ]; then
					cat "$f_path"/part-* | $TAR --zstd -x -f - -C "$path"
				else
					$TAR --zstd -x -f "$f_path" -C "$path"
				fi
				# if the day is 01 the the full backup is recovered so we need to clean newer files created after the backup date.
				if [ "$DAY_OF_MONTH" = "01" ]; then
					del_res "$path" "$2" "$3" "$TMP_DIR"
				fi
			done
			for i_path in $arh; do
				# Skip full backups as they were already processed (redundant but safe)
				[[ "$(basename "$i_path")" =~ ^full- ]] && continue
				
				i=$(basename "$i_path")
				echo -en "\tExtracting $i (from $(dirname "$i_path"))...\n\n"
				if [ -d "$i_path" ]; then
					cat "$i_path"/part-* | $TAR --zstd -x -f - -C "$path"
				else
					$TAR --zstd -x -f "$i_path" -C "$path"
				fi
			done
			del_res "$path" "$2" "$3" "$TMP_DIR"
		else
			mesaj="Invalid directory to restore!"
		fi
	elif [ "$type" = "db" ]; then
		db=$2
		# here we build the db list to restore from the files we backed up before in the day requested
		dblist="$dblist all"
		#echo $dblist
		for d in $dblist; do
			if [ "$d" == "$2" ] || [ "$2" == "all" ]; then
				if [ "$2" = "all" ]; then
					# get db list from backup and restore all db's
					arh=$(find "$DB_ROOT" -maxdepth 2 \( -type f -o -type d \) 2>/dev/null | grep "/db-" | grep $YDATE-$MONTH_DATE-$DAY_OF_MONTH | grep -v "\.sha256$")
				else
					arh=$(find "$DB_ROOT" -maxdepth 2 \( -type f -o -type d \) 2>/dev/null | grep "/db-$db/" | grep $YDATE-$MONTH_DATE-$DAY_OF_MONTH | grep -v "\.sha256$")
				fi
				for i in $arh; do
					rdb=$(basename "$i" | cut -d "-" -f2)
					mysql --user="$DB_USER" --password="$DB_PASSWORD" --execute "CREATE DATABASE IF NOT EXISTS $rdb;"
					if [ -d "$i" ]; then
						cat "$i"/part-* | $TAR --zstd -xOf - | mysql --user="$DB_USER" --password="$DB_PASSWORD" --database="$rdb"
					else
						$TAR --zstd -xOf "$i" | mysql --user="$DB_USER" --password="$DB_PASSWORD" --database="$rdb"
					fi
				done
				echo -en "All restore jobs done!\nDatabase $2 restored to date $3!\n"
			fi
		done

		if [ -z "$rdb" ]; then
			mesaj="Invalid database to restore!"
		fi
	else
		print_usage
		mesaj="Invalid type specified"
	fi

	if [ -n "$mesaj" ]; then
		print_usage
		echo -en "\t\t###\t$mesaj\t###\n\n"
	fi

	# Send accumulated maildata an cleanup
	if [ -n "${MAIL_BIN:-}" ]; then
		${MAIL_BIN} -s "Backup of $COMPUTER $(date +'%F')" -r "$EMAIL_FROM" "$EMAIL_TO" < "$TMP_DIR/maildata"
	fi
	rm -rf "$TMP_DIR/datestart"
	rm -rf "$TMP_DIR/dateend"
	rm -rf "$TMP_DIR/excluded"
	rm -rf "$TMP_DIR/maildata"
}

case "${1:-}" in
-h|--help)
	print_usage
	exit 0
	;;
-v|--version|version)
	echo $headline
	echo -e "\nVersion $version\n"
	exit 0
	;;
dir)
	restore "${1:-}" "${2:-}" "${3:-}" "${4:-}"
	;;
db)
	restore "${1:-}" "${2:-}" "${3:-}" "${4:-}"
	;;
*)
	backup "$@"
	exit 1
esac
