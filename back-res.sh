#! /bin/bash
version="0.10.0 from 2021-04-24"
# Always download the latest version here: http://www.eurosistems.ro/back-res
# Thanks or questions: http://www.howtoforge.com/forums/showthread.php?t=41609
#
# CHANGELOG:
# -----------------------------------------------------------------------------
# version 0.10.0 - 2021-04-24 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
# --------------------------
# - Changed mysql import command for import stored functions too
# - Changed variable names for more readability
# - Change compress command line for compatibility with tar new version
# - Change the day of full backup. Now the full backup will be performed whenever there is no one for the current month
# - Change Log file name in $BACKUP_DIR/log/backup-$FULL_DATE.log
# -----------------------------------------------------------------------------
# version 0.9.6 - 2014-02-04 (by Yavuz Aydin - Vrij Media)
# --------------------------
# - Changed mysql import routine to create database if it doesn't exist
# - Changed code to import database
# -----------------------------------------------------------------------------
# version 0.9.5 - 2014-01-25 (by Yavuz Aydin - Vrij Media)
# --------------------------
# - Removed /var from DIRECTORIES
# - Added code to add all subdirectories of /var excluding /var/www and
#   /var/vmail to DIRECTORIES
# - Added code to add /var/www excluding subdirectories of /var/www/clients,
#   all subdirectories of /var/www/clients and all subdirectories of /var/vmail
#   to DIRECTORIES
# - Changed variable COMPUTER to take computername from hostname -f
# -----------------------------------------------------------------------------
# version 0.9.4 - 2010-09-13
# --------------------------
# Small fix: - Corrected small bug replaced tar with $TAR in the recovery line
#	of the databases. (The line: mysql -u$DB_USER -p$DB_PASSWORD $rdb <)
#	Thanks goes to Nimarda and colo.
# -----------------------------------------------------------------------------
# version 0.9.3 - 2010-08-01
# --------------------------
# Small fix: - Modified del_old_files function to remove "/" from the $to_del
#	variable used to delete old files
#	 - Removed from del_old_files function the section used to keep old
#	databases (It's not working if there is no space left on device). Added
#	in TODO section
# -----------------------------------------------------------------------------
# version 0.9.2 - 2010-04-18
# --------------------------
# Always download the latest version here: http://www.eurosistems.ro/back-res
# Thanks or questions: http://www.howtoforge.com/forums/showthread.php?t=41609
#
# Fixes: - First run now does not gives errors (Thanks nokia80, Snake12,
#	rudolfpietersma, HyperAtom, jmp51483, bseibenick, dipeshmehta, andypl
#	and all others)
#	 - Modified the log function to accept first time dir createin
#	 - Modified the starting sequence to not check the free space if the
#	primary backup directory does not exist
#	 - If primary backup dir does not exist now it's created at the start
#	 - Added a line to remove the maildata at the start if the user stops
#	the script before finishing his jobs. This prevents the script to send
#	incorect mails.
#	 - Added link http://www.howtoforge.com/forums/showthread.php?t=41609
#	maybe some of the downloaders will visit the forum.
#	 - Added first TODO
# -----------------------------------------------------------------------------
# beta version 0.9.1 - first public release last modified 2009-12-06
# moved to http://www.eurosistems.ro/back-res.0.9.1
# -----------------------------------------------------------------------------
# TODO:
#	 - Add required files check (tar, bzip2, mail, etc.)
#	 - Create a better del_old_files function (2010-08-01)
#	 - If you need anything else I'll be happy to do it in my spare time if
#	you ask here: http://www.howtoforge.com/forums/showthread.php?t=41609
#
# Copyright (c) go0ogl3 gabi@eurosistems.ro
# If you want to reward my work donate a small amount with Paypal (use my mail)
#
# If you enjoy my script please register and say thank you here:
# http://www.howtoforge.com/forums/showthread.php?t=41609
# This is to keep the thread alive so this script can help other people too.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# The above copyright notice and this permission notice shall be included in
# all copies of the script.

# description: A backup and restore script for databases and directories
#
# The state of development is "It works for me"!
# So don't blame me if anything bad will happen to you or to your computer
# if you use this script.
# I've done my best to make myself understood if you read on.
#
# Detailed Description
#
# Full dir, mysql and incremental backup script
# Full and incremental restore script
# It's meant to use minimum resources and space and keep a loooong backup.
# I've tried to make as more checks as possible but I can't beat "smart" users.
# Weird things can happen if your backup dirs includes the "-" or "_" chars.
# Those chars are used by this script and files formed by the script.

### Backup part -=============================
#
# Important!!! Make sure your system has a correct date. Suggestion: use ntp.
# Backup is not meant to be interactive, it's meant to be run daily from cron.
# That's why the log for backup is kept in logdir $LOG_FILE
# On the first time of the month a permanet full backup is made.
# The rest of the time an incremental backup is made, by date.
# Databases are at full allways and the script makes an automatic repair and
# optimizes the databases before the backup.

### Warning!!! ###
# If you set the "DELETE_OLD" variable to "yes" the script will delete the old
# backups to make room for the new ones. Read on.

### Warning!!! ###
# All incremental backups and databases for a month will be deleted if space
# is less than the maximum percent of used space "MAX_PERCENT_OF_USED_SPACE".

# You need to take care to not enter in an endless loop if you set DELETE_OLD="yes"
# The loop can happen if deleted files form $BACKUP_DIR don't decrease the
# percent of used space
# The script check for some dirs and files and it's supposed to be run as root
# The script is supposed to be run daily from cron at night like
# 40 3 * * * /usr/local/bin/backup-restore.sh 1>/dev/null 2>/dev/null
# This scripts verifies and corrects all errors found in ALL mysql databases
# The script also makes full backups of ALL mysql databases every time it's run
#
# Restore part -============================

# Restore is meant to be little interactive, the messages are on standard output
# Dir's are restored verbose with tar by default.
# Last minute of the day "$LAST_MINUTE_OF_THE_DAY" is set to 2359 but the backup is started at 03:40
# so this should be set AFTER the backup has ended! At 23:59 of the backup day
# we can have many files modified from the 03:40. The not so perfect solution is
# to backup later in the day (23:00) and hope the backup finishes until 23:59
# My server is still loaded on the 23:00, so I use 03:40 in cron and LAST_MINUTE_OF_THE_DAY=2359
# because a full backup last for more than 16 hours for tar.bz2
# For sure I will loose all files created between 03:40 and 23:59 of that day.
# To prevent that I can restore files one day AFTER the day I want to restore
# and use find --newer to delete unwanted files.

# To restore dirs make sure you have the full backup from that month and use:
# `back-res dir /etc 2009-11-23 /`
# to restore the "/etc" dir from date 2009-11-23 to root
# `back-res dir /etc 2009-11-23 /tmp` is used to restore the "/etc" dir to /tmp
#
# `back-res dir all 2009-11-23 /`
# to restore all directories from date 2009-11-23 to root

# To restore databases use:
# `back-res db mysql 2009-11-23`
# to restore the "mysql" database from date 2009-11-23 to local mysql server
#
# `back-res db all 2009-11-23`
# to restore all databases from date 2009-11-23 to local mysql server


###############################
### Begin variables section ###
###############################

# Change the variables below to fit your computer/backup

COMPUTER=$(hostname -f)					# name of this computer
DIRECTORIES="/etc"						# directories to backup (DO NOT ADD VAR_DIR HERE!)
VAR_DIR="/var"
WWW_DIR="www"							# Directory holding websites (global) (must reside in VAR_DIR!)
CLIENTS_DIR="clients"					# Directory holding websites per client (must reside in WWW_DIR!)
MAIL_DIR="vmail"						# Directory holding mail (must reside in VAR_DIR!)
DB_USER="root"							# database user
DB_PASSWORD=$(cat /usr/local/ispconfig/server/lib/mysql_clientdb.conf | grep '$clientdb_password' | cut -d"'" -f 2)				# database password
EMAIL_FROM="$(hostname)@$(hostname -d)"
EMAIL_TO="info@example.com"		# mail for the responsible person
TAR=$(which tar)						# name and location of tar
BZIP2=$(which bzip2)					# name and location of bzip2
COMPRESS_ARGS="-cjpSPf"		#sparse		# tar arguments P = removed /.
EXTRACT_ARGS="-xjpf"					# tar extract arguments P = removed /
TMP_DIR="/var/tmp/backup-restore"		# temp dir for database dump and other stuff
mkdir -p $TMP_DIR
DELETE_OLD="yes"						# Enable delete of files if used space percent > than $MAX_PERCENT_OF_USED_SPACE (yes or anything else)
MAX_PERCENT_OF_USED_SPACE="70"			# Max percent of used space before start of delete
LAST_MINUTE_OF_THE_DAY="2359"			# last minute of the day = last minute of the restored backup of the day restored
BACKUP_DIR="/var/backup-restore/${COMPUTER}"	# where to store the backups
EXCLUDED=" *.lck *.lock *.pid *.sock
/dev /lib/init/rw /media /proc /srv /sys /tmp
/var/adm /var/amavis $BACKUP_DIR /var/cache /var/crash
/var/lib/amavis /var/lib/apache2/fcgid /var/lib/mysql /var/lock /var/log/verlihub
/var/run /var/spool/postfix/p* /var/spool/postfix/var /var/spool/postfix/dev/log
/var/tmp /var/www/owncloud /var/www/roundcube /var/www/seafile"			# exclude those dir's and files

###################################
### End user editable variables ###
###################################

#########################################################
# You should NOT have to change anything below here     #
#########################################################

# Add /var excluding subdirectories /var/www and /var/vmail to DIRECTORIES
if [[ -d $VAR_DIR ]]; then
	for i in $(ls -a $VAR_DIR); do
		if [[ "$i" != "." && "$i" != ".." && "$i" != $WWW_DIR && "$i" != $MAIL_DIR ]]; then
			DIRECTORIES=$DIRECTORIES" "$VAR_DIR"/"$i
		fi
	done
fi

# Add /var/www excluding subdirectories of /var/www/clients and all subdirectories of /var/www/clients to DIRECTORIES
if [[ -d $VAR_DIR"/"$WWW_DIR ]]; then
	for i in $(ls -a $VAR_DIR/$WWW_DIR); do
		if [[ "$i" != "." && "$i" != ".." && "$i" != "$CLIENTS_DIR" ]]; then
			DIRECTORIES=$DIRECTORIES" "$VAR_DIR"/"$WWW_DIR"/"$i
		fi
	done
	for i in $(ls -a $VAR_DIR/$WWW_DIR/$CLIENTS_DIR); do
		if [[ "$i" != "." && "$i" != ".." ]]; then
			if [[ -d $VAR_DIR"/"$WWW_DIR"/"$CLIENTS_DIR"/"$i ]]; then
				for j in $(ls -a $VAR_DIR/$WWW_DIR/$CLIENTS_DIR/$i); do
					if [[ "$j" != "." && "$j" != ".." ]]; then
						DIRECTORIES=$DIRECTORIES" "$VAR_DIR"/"$WWW_DIR"/"$CLIENTS_DIR"/"$i"/"$j
					fi
				done
			else
				DIRECTORIES=$DIRECTORIES" "$VAR_DIR"/"$WWW_DIR"/"$CLIENTS_DIR"/"$i
			fi
		fi
	done
fi

# Add all subdirectories of MAIL_DIR to DIRECTORIES
if [[ -d $VAR_DIR"/"$MAIL_DIR ]]; then
	for i in $(ls -a $VAR_DIR/$MAIL_DIR); do
		if [[ "$i" != "." && "$i" != ".." ]]; then
			DIRECTORIES=$DIRECTORIES" "$VAR_DIR"/"$MAIL_DIR"/"$i
		fi
	done
fi

me=$(basename $0)
headline="
---------------------=== The back-res script by go0ogl3 ===---------------------
"
usage="$headline
The backup part requires some configuration in the header of the script
and it's supposed to be run from cron.
The restore part it's supposed to be run from command line.
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
"

backup () {
	if [ -n "$1" ]; then
		echo -e "$usage"
		exit
	fi

	MONTH_DATE=$(date +%Y-%m)					# Date, YYYY-MM, eg. 2009-09
	DAY_OF_MONTH=$(date +%d)					# Date of the Month, DD, eg. 27
	FULL_DATE="${MONTH_DATE}-${DAY_OF_MONTH}"	# Full Date, YYYY-MM-DD, year sorted, eg. 2009-11-21
	LOG_FILE=$BACKUP_DIR/log/backup-$FULL_DATE.log

	#################
	### Functions ###
	#################

	function log {
		NOW=$(date "+%Y-%m-%d %H:%M:%S")		# I like this type of date. Syslog type doesn't use the year.
		if [ -e $LOG_FILE ]; then
			echo "$NOW - $(basename $0) - $1" >> $LOG_FILE
			echo "$NOW - $(basename $0) - $1" >> $TMP_DIR/maildata
		else
			if [ ! -d $BACKUP_DIR/log ]; then
				mkdir -p $BACKUP_DIR/log
				if [ -n "$log1" ]; then
					echo "$log1" >> $LOG_FILE
					echo "$log1" >> $TMP_DIR/maildata
				fi
				echo "$NOW - $(basename $0) - First run: log dir and log file created." >> $LOG_FILE
				echo "$NOW - $(basename $0) - First run: log dir and log file created." >> $TMP_DIR/maildata
			else
				echo "$NOW - $(basename $0) - First run: log file created." >> $LOG_FILE
				echo "$NOW - $(basename $0) - First run: log file created." >> $TMP_DIR/maildata
			fi
				echo "$NOW - $(basename $0) - $1" >> $LOG_FILE
				echo "$NOW - $(basename $0) - $1" >> $TMP_DIR/maildata
		fi
	}

	function check_mdir {
		log "Checking if month dir exist: $BACKUP_DIR/$MONTH_DATE"
		if [ -d $BACKUP_DIR/$MONTH_DATE ]; then
			log "Backup dir $BACKUP_DIR/$MONTH_DATE exists"
		else
			mkdir $BACKUP_DIR/$MONTH_DATE
			log "Month dir $BACKUP_DIR/$MONTH_DATE created"
		fi
	}

	function check_tempdir {
		log "Checking if temp dir exist: $TMP_DIR"
		if [ -d $TMP_DIR ]; then
			log "Temp dir $TMP_DIR exists"
		else
			mkdir $TMP_DIR
			log "Temp dir $TMP_DIR created"
		fi
	}

	function del_old_files {
		to_del=$(ls -ctF $BACKUP_DIR | grep -v ^log/ | tail -n 1 | sed 's/\///g') # sort files in ctime order and select the first modified, except the log dir
		#if [ -d "$BACKUP_DIR/$to_del" ]; then
		#    # recover db backups and store only the ones from de first day of month or from the first full backup of dirs
		#    # list all db backups in month dir, extract first date
		#    day=$(ls -ct $BACKUP_DIR/$to_del | tail -n 1 | cut -d "-" -f 5 | cut -d "." -f 1)
		#    # then list all db file names
		#    dblist=$(ls -ct $BACKUP_DIR/$to_del | grep $to_del-$day)
		#    for db in $dblist; do
		#	 mv $BACKUP_DIR/$to_del/$db $BACKUP_DIR/$db	# moving files keeps creation date
		#    done
		#	log "Kept db's from $to_del-$day"
		#else
			rm -rf $BACKUP_DIR/$to_del
			log "Deleted old: $BACKUP_DIR/$to_del"
			count=0
			while [ $count -lt 3 ]; do
				count=$(($count+1))
				#echo $count argmax # for test
				check_space
			done
		#fi
	}

	#PERCENT_OF_USED_DISK="95" # for test

	function check_space {
		#PERCENT_OF_USED_DISK=$((PERCENT_OF_USED_DISK-1)) # for test
		PERCENT_OF_USED_DISK=$(df -h $BACKUP_DIR | awk 'NR==2{print $5}' | cut -d% -f 1)
		#PERCENT_OF_USED_DISK="90"

		if [ $PERCENT_OF_USED_DISK -gt $MAX_PERCENT_OF_USED_SPACE ];then
			log "There is $PERCENT_OF_USED_DISK% space used on $BACKUP_DIR"
			if [ $DELETE_OLD = "yes" ]; then
				del_old_files
			else
				log "No free space and DELETE_OLD=$DELETE_OLD so we abort here and send mail to $EMAIL_TO"
				mail -s "Daily backup of $COMPUTER $(date +'%F')" -r "$EMAIL_FROM" "$EMAIL_TO" < $TMP_DIR/maildata
				exit
			fi
		else
			log "Percent used space $PERCENT_OF_USED_DISK% on $BACKUP_DIR ok."
		fi
	}

	function db_back {
		#Replace / with _ in dir name => filename
		#DIR_NAME=$(echo "$DIRECTORIES" | awk '{gsub("/", "_", $0); print}')

		### All db's check and correct any errors found

		log "Starting automatic repair and optimize for all databases..."
		mysqlcheck -u$DB_USER -p$DB_PASSWORD --all-databases --optimize --auto-repair --silent 2>&1
		### Starting database dumps
		for i in $(mysql -u$DB_USER -p$DB_PASSWORD -Bse 'show databases'); do
			log "Starting mysqldump $i"
			$(mysqldump -u$DB_USER -p$DB_PASSWORD $i --allow-keywords --comments=false --routines --triggers --add-drop-table > $TMP_DIR/db-$i-$FULL_DATE.sql)
			$TAR $COMPRESS_ARGS $BACKUP_DIR/$MONTH_DATE/db-$i-$FULL_DATE.tar.bz2 -C $TMP_DIR db-$i-$FULL_DATE.sql
			rm -rf $TMP_DIR/db-$i-$FULL_DATE.sql
			log "Dump OK. $i database saved OK!"
		done
	}

	#############
	### START ###
	#############
	rm -f $TMP_DIR/maildata
	if [ -d $BACKUP_DIR ]; then
		check_space
	else
		mkdir -p $BACKUP_DIR
		log "$(basename $0) - First run: primary dir $BACKUP_DIR created."
	fi
	check_mdir
	check_tempdir
	rm -rf $TMP_DIR/excluded
	for a in $(echo $EXCLUDED) ; do
		exfile=$(echo -e $a >> $TMP_DIR/excluded)
	done
	db_back

	for i in $(echo $DIRECTORIES) ; do
		UNDERSCORED_DIR=$(echo $i | awk '{gsub("/", "_", $0); print}')
		TARGET_DIR=$(echo $i | awk '{print $1}')
		FULL_BACKUP_FILE=$(ls $BACKUP_DIR | grep ^full$UNDERSCORED_DIR-${MONTH_DATE}-)
		if [ -z $FULL_BACKUP_FILE ]; then
			# Monthly full backup
			log "No full backup found for $TARGET_DIR in this month. Full backup now!"
			echo > $TMP_DIR/full-backup$UNDERSCORED_DIR.lck
			echo "$TARGET_DIR"
			$TAR $COMPRESS_ARGS $BACKUP_DIR/full$UNDERSCORED_DIR-$FULL_DATE.tar.bz2 -X $TMP_DIR/excluded $TARGET_DIR
			log "Full montly backup of $TARGET_DIR done."
		else
			# If there is already a full backup for this month, let's do the incremental backup
			if [ ! -e $TMP_DIR/full-backup$UNDERSCORED_DIR.lck ]; then
				log "Starting daily backup for: $TARGET_DIR"
				echo "$TARGET_DIR"
				NEWER="--newer $FULL_DATE"
				$TAR $NEWER $COMPRESS_ARGS $BACKUP_DIR/$MONTH_DATE/i$UNDERSCORED_DIR-$FULL_DATE.tar.bz2 -X $TMP_DIR/excluded $TARGET_DIR
				log "Daily backup for $TARGET_DIR done."
			else
				log "Lock file for $TARGET_DIR full backup exists!"
			fi
		fi
		# Clean full backup directory lock file
		rm -rf $TMP_DIR/full-backup$UNDERSCORED_DIR.lck
	done

	#Clean temp dir
	rm -rf $TMP_DIR/excluded
	# End of script
	log "All backup jobs done. Exiting script!"
	mail -s "Daily backup of $COMPUTER `date +'%F'`" -r "$EMAIL_FROM" "$EMAIL_TO" < $TMP_DIR/maildata
}

restore() {
	del_res() {
		# We now need to remove the newer files created after the restored backup date.
		to_rem=$(find $path/$2 -newer $TMP_DIR/dateend)
		echo -en "\n$headline\n    For a clean backup restored at $3 we need now to delete the files\ncreated after the backup date.\n    If exists, a list of files to be deleted follows:\n\n"
			for a in $to_rem; do
				echo -e "To be removed: $a"
			done
		echo -en "\nPlease input \"yes\" to delete those files, if they exist, and press [ENTER]: "
		read del
		if [[ "$del" = "yes" ]]; then
			for a in $to_rem; do
				rm -rf $a
			done
			echo -en "All restore jobs done!\nDir $2 restored to date $3!\n"
			exit
		fi
	}

	if [ -z "$4" ]; then
		path="/"
	else
		path=$4					# this is the path where to extract the files
	fi

	RDATE=$3
	DAY_OF_MONTH=$(echo $RDATE | cut -d "-" -f3)		# Date of the Month eg. 27
	MONTH_DATE=$(echo $RDATE | cut -d "-" -f2)
	YDATE=$(echo $RDATE | cut -d "-" -f1)

	type=$1
	dir=$(echo $2 | awk '{gsub("/", "_", $0); print}')

	if [ -z "$3" ]; then
		echo -e "$usage"
		exit
	fi

	# poor date input verification: ${#RDATE} is 10 for a correct date 2009-01-30
	# find the first possible restore date=day
	year=$(ls -ctF $BACKUP_DIR | grep -v ^log/ | tail -n 1 | cut -d "-" -f 2)
	md=$(ls -ctF $BACKUP_DIR | grep -v ^log/ | tail -n 1 | cut -d "-" -f 3)
	day=$(ls -ctF $BACKUP_DIR | grep -v ^log/ | tail -n 1 | cut -d "-" -f 4 | cut -d "." -f 1)
	resdate=$year$md$day

	dh="1234"
	err=$(touch -t $YDATE$MONTH_DATE$DAY_OF_MONTH$dh $TMP_DIR/datestart 2>&1)

	if [ -n "$err" ] & [ ${#RDATE} != 10 ]; then
		#echo "err = $err"
		echo -e "$usage"
		echo -e "Invalid date format. Correct YYYY-MM-DD. Ex.: 2009-01-14\n"
		exit
	fi

	# check to see if user inputs date in future
	TD=$(date +%s) # today in epoch
	ID=$(date --date "$RDATE" +%s) # input date in epoch
	RD=$(date --date "$resdate" +%s) # first backup date in epoch

	if [ "$ID" -ge "$TD" ]; then
		echo -e "$usage"
		echo -e "Invalid date format. Date supplied $RDATE is in the future!\n"
		exit
	fi

	if [ "$RD" -gt "$ID" ]; then
		echo -e "$usage"
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
				if [[ "$DIRECTORIES all" =~ "$2" ]]; then
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
	if [ $type = "dir" ]; then
		if [[ "$DIRECTORIES all" =~ "$2" ]]; then
			if [ $dir = "all" ]; then
				farh=$(find $BACKUP_DIR -maxdepth 1 -type f -newer $TMP_DIR/datestart -a ! -newer $TMP_DIR/dateend | sed 's_.*/__' | grep ^full_)
				arh=$(find $BACKUP_DIR/$YDATE-$MONTH_DATE -maxdepth 1 -type f -newer $TMP_DIR/datestart -a ! -newer $TMP_DIR/dateend | sed 's_.*/__' | grep -v ^db-)
				# echo farh este $farh
				# echo arh este $arh
			else
				farh=$(find $BACKUP_DIR -maxdepth 1 -type f -newer $TMP_DIR/datestart -a ! -newer $TMP_DIR/dateend | sed 's_.*/__' | grep $dir | grep ^full_)
				# echo farh e $farh
				arh=$(find $BACKUP_DIR/$YDATE-$MONTH_DATE -maxdepth 1 -type f -newer $TMP_DIR/datestart -a ! -newer $TMP_DIR/dateend | sed 's_.*/__' | grep $dir | grep -v ^db-)
				# echo arh e $arh
			fi
			for f in $farh; do
				echo -en "\tExtracting $f...\n\n"
				$TAR $EXTRACT_ARGS $BACKUP_DIR/$f -C $path &>/dev/null
				# if the day is 01 the the full backup is recovered so we need to clean newer files created after the backup date.
				if [ $DAY_OF_MONTH = "01" ]; then
					del_res $path $2 $3 $TMP_DIR
				fi
			done
			for i in $arh; do
				echo -en "\tExtracting $i...\n\n"
				$TAR $EXTRACT_ARGS $BACKUP_DIR/$YDATE-$MONTH_DATE/$i -C $path &>/dev/null
			done
			del_res $path $2 $3 $TMP_DIR
		else
			mesaj="Invalid directory to restore!"
		fi
	elif [ "$type" = "db" ]; then
		db=$2
		# here we build the db list to restore from the files we backed up before in the day requested
		dblist=$(find  $BACKUP_DIR/$YDATE-$MONTH_DATE -maxdepth 1 -type f | sed 's_.*/__' | grep ^db- | grep $YDATE-$MONTH_DATE-$DAY_OF_MONTH | cut -d "-" -f2)
		dblist="$dblist all"
		#echo $dblist
		for d in $dblist; do
			if [ "$d" == "$2" ]; then
				if [ "$db" = "all" ]; then
					# get db list from backup and restore all db's
					arh=$(find  $BACKUP_DIR/$YDATE-$MONTH_DATE -maxdepth 1 -type f | sed 's_.*/__' | grep ^db- | grep $YDATE-$MONTH_DATE-$DAY_OF_MONTH)
				else
					arh=$(find  $BACKUP_DIR/$YDATE-$MONTH_DATE -maxdepth 1 -type f | sed 's_.*/__' | grep ^db- | grep $db- | grep $YDATE-$MONTH_DATE-$DAY_OF_MONTH)
				fi
				for i in $arh; do
					rdb=$(echo $i | cut -d "-" -f2)
					mysql --user="$DB_USER" --password="$DB_PASSWORD" --execute "CREATE DATABASE IF NOT EXISTS $rdb;"
					$BZIP2 -dc $BACKUP_DIR/$YDATE-$MONTH_DATE/$i | $TAR -xvO | mysql --user="$DB_USER" --password="$DB_PASSWORD" --database=$rdb
				done
				echo -en "All restore jobs done!\nDatabase $2 restored to date $3!\n"
			fi
		done

		if [ -z "$rdb" ]; then
			mesaj="Invalid database to restore!"
		fi
	else
		echo -e "$usage"
		mesaj="Invalid type specified"
	fi

	if [ -n "$mesaj" ]; then
		echo -e "$usage"
		echo -en "\t\t###\t$mesaj\t###\n\n"
	fi

	# Send accumulated maildata an cleanup
	mail -s "Daily backup of $COMPUTER $(date +'%F')" -r "$EMAIL_FROM" "$EMAIL_TO" < $TMP_DIR/maildata
	rm -rf $TMP_DIR/datestart
	rm -rf $TMP_DIR/dateend
	rm -rf $TMP_DIR/excluded
	rm -rf $TMP_DIR/maildata
}

case "$1" in
dir)
	restore $1 $2 $3 $4
	;;
db)
	restore $1 $2 $3 $4
	;;
version)
	echo $headline
	echo -e "\nVersion $version\n"
	;;
*)
	backup $1
	exit 1
esac
