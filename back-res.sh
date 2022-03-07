#!/bin/bash
version="0.9.6 from 2014-02-04"
# Always download the latest version here: http://www.eurosistems.ro/back-res
# Thanks or questions: http://www.howtoforge.com/forums/showthread.php?t=41609
#
# CHANGELOG:
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
#	of the databases. (The line: mysql -u$dbuser -p$dbpassword $rdb <)
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
# TODO:	 - Add required files check (tar, bzip2, mail, etc.)
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
# That's why the log for backup is kept in logdir $BACKUPDIR/log/backup.log
# On the 1st of the month a permanet full backup is made.
# The rest of the time an incremental backup is made, by date.
# Databases are at full allways and the script makes an automatic repair and
# optimizes the databases before the backup.

### Warning!!! ###
# If you set the "del_en" variable to "yes" the script will delete the old
# backups to make room for the new ones. Read on.

### Warning!!! ###
# All incremental backups and databases for a month will be deleted if space
# is less than the maximum percent of used space "maxp".

# You need to take care to not enter in an endless loop if you set del_en="yes"
# The loop can happen if deleted files form $BACKUPDIR don't decrease the
# percent of used space
# The script check for some dirs and files and it's supposed to be run as root
# The script is supposed to be run daily from cron at night like
# 40 3 * * *      /etc/back-res 1>/dev/null 2>/dev/null
# This scripts verifies and corrects all errors found in ALL mysql databases
# The script also makes full backups of ALL mysql databases every time it's run
#
# Restore part -============================

# Restore is meant to be little interactive, the messages are on standard output
# Dir's are restored verbose with tar by default.
# Last minute of the day "$hm" is set to 2359 but the backup is started at 03:40
# so this should be set AFTER the backup has ended! At 23:59 of the backup day
# we can have many files modified from the 03:40. The not so perfect solution is
# to backup later in the day (23:00) and hope the backup finishes until 23:59
# My server is still loaded on the 23:00, so I use 03:40 in cron and hm=2359
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

COMPUTER=`hostname -f`					# name of this computer
DIRECTORIES="/bin /boot /etc /home /lib /lib64 /root
/sbin /usr /www"					# directories to backup (DO NOT ADD VARDIR HERE!)
VARDIR="/var"
WWWDIR="www"						# Directory holding websites (global) (must reside in VARDIR!)
CLIENTSDIR="clients"					# Directory holding websites per client (must reside in WWWDIR!)
MAILDIR="vmail"						# Directory holding mail (must reside in VARDIR!)
EXCLUDED="/bck /tmp /dev /proc /sys /srv /media
/var/adm /var/cache /var/lib/mysql
/var/run /var/lock /lib/init/rw /var/tmp
/var/log/verlihub /var/lib/amavis /var/amavis /var/spool/postfix/p*
/var/spool/postfix/var *.pid *.lock *.lck"		# exclude those dir's and files
BACKUPDIR="/bck/$COMPUTER"				# where to store the backups
dbuser="root"						# database user
dbpassword="yourpassword"				# database password
email="backup@yourdomain.com"				# mail for the responsible person
TAR=`which tar`						# name and location of tar
BZIP2=`which bzip2`					# name and location of bzip2
ARG="-cjpSPf"		#sparse				# tar arguments P = removed /.
EARG="-xjpf"						# tar extract arguments P = removed /
tmpdir="/tmp/tmpbck"					# temp dir for database dump and other stuff
del_en="yes"						# Enable delete of files if used space percent > than $maxp (yes or anything else)
maxp="85"						# Max percent of used space before start of delete
hm="2359"						# last minute of the day = last minute of the restored backup of the day restored

###################################
### End user editable variables ###
###################################

#########################################################
# You should NOT have to change anything below here     #
#########################################################

# Add /var excluding subdirectories /var/www and /var/vmail to DIRECTORIES
if [[ -d $VARDIR ]]; then
  for i in `ls -a $VARDIR`; do
    if [[ "$i" != "." && "$i" != ".." && "$i" != $WWWDIR && "$i" != $MAILDIR ]]; then
      DIRECTORIES=$DIRECTORIES" "$VARDIR"/"$i
    fi
  done
fi

# Add /var/www excluding subdirectories of /var/www/clients and all subdirectories of /var/www/clients to DIRECTORIES
if [[ -d $VARDIR"/"$WWWDIR ]]; then
  for i in `ls -a $VARDIR/$WWWDIR`; do
    if [[ "$i" != "." && "$i" != ".." && "$i" != "$CLIENTSDIR" ]]; then
      DIRECTORIES=$DIRECTORIES" "$VARDIR"/"$WWWDIR"/"$i
    fi
  done
  for i in `ls -a $VARDIR/$WWWDIR/$CLIENTSDIR`; do
    if [[ "$i" != "." && "$i" != ".." ]]; then
      if [[ -d $VARDIR"/"$WWWDIR"/"$CLIENTSDIR"/"$i ]]; then
        for j in `ls -a $VARDIR/$WWWDIR/$CLIENTSDIR/$i`; do
          if [[ "$j" != "." && "$j" != ".." ]]; then
            DIRECTORIES=$DIRECTORIES" "$VARDIR"/"$WWWDIR"/"$CLIENTSDIR"/"$i"/"$j
          fi
        done
      else
        DIRECTORIES=$DIRECTORIES" "$VARDIR"/"$WWWDIR"/"$CLIENTSDIR"/"$i
      fi
    fi
  done
fi

# Add all subdirectories of MAILDIR to DIRECTORIES
if [[ -d $VARDIR"/"$MAILDIR ]]; then
  for i in `ls -a $VARDIR/$MAILDIR`; do
    if [[ "$i" != "." && "$i" != ".." ]]; then
      DIRECTORIES=$DIRECTORIES" "$VARDIR"/"$MAILDIR"/"$i
    fi
  done
fi

me=`basename $0`
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

if [ -n "$1" ] ; then
echo -e "$usage"
exit
fi

DOM=`date +%d`			# Date of the Month, DD, eg. 27
FDATE=`date +%F`		# Full Date, YYYY-MM-DD, year sorted, eg. 2009-11-21
MDATE=`date +%Y-%m`		# Date, YYYY-MM, eg. 2009-09

#################
### Functions ###
#################

function log {
    acum=`date "+%Y-%m-%d %H:%M:%S"` # I like this type of date. Syslog type doesn't use the year.
	if [ -e $BACKUPDIR/log/backup.log ]; then
	    echo "$acum - `basename $0` - $1" >> $BACKUPDIR/log/backup.log
	    echo "$acum - `basename $0` - $1" >> $tmpdir/maildata
	else
	    if [ ! -d $BACKUPDIR/log ]; then
		mkdir $BACKUPDIR/log
		if [ -n "$log1" ]; then
		echo "$log1" >> $BACKUPDIR/log/backup.log
		echo "$log1" >> $tmpdir/maildata
		fi
		echo "$acum - `basename $0` - First run: log dir and log file created." >> $BACKUPDIR/log/backup.log
		echo "$acum - `basename $0` - First run: log dir and log file created." >> $tmpdir/maildata
	    else
		echo "$acum - `basename $0` - First run: log file created." >> $BACKUPDIR/log/backup.log
		echo "$acum - `basename $0` - First run: log file created." >> $tmpdir/maildata
	    fi
	    echo "$acum - `basename $0` - $1" >> $BACKUPDIR/log/backup.log
	    echo "$acum - `basename $0` - $1" >> $tmpdir/maildata
	fi
}

function check_mdir {
    log "Checking if month dir exist: $BACKUPDIR/$MDATE"
    if [ -d $BACKUPDIR/$MDATE ] ; then
	log "Backup dir $BACKUPDIR/$MDATE exists"
    else
	mkdir $BACKUPDIR/$MDATE
        log "Month dir $BACKUPDIR/$MDATE created"
    fi
}

function check_tempdir {
    log "Checking if temp dir exist: $tmpdir"
    if [ -d $tmpdir ] ; then
	log "Temp dir $tmpdir exists"
    else
	mkdir $tmpdir
        log "Temp dir $tmpdir created"
    fi
}

function del_old_files {
    to_del=`ls -ctF $BACKUPDIR | grep -v ^log/ | tail -n 1 | sed 's/\///g'` # sort files in ctime order and select the first modified, except the log dir
#if [ -d "$BACKUPDIR/$to_del" ] ; then
#    # recover db backups and store only the ones from de first day of month or from the first full backup of dirs
#    # list all db backups in month dir, extract first date
#    day=`ls -ct $BACKUPDIR/$to_del | tail -n 1 | cut -d "-" -f 5 | cut -d "." -f 1`
#    # then list all db file names
#    dblist=`ls -ct $BACKUPDIR/$to_del | grep $to_del-$day`
#    for db in $dblist; do
#	mv $BACKUPDIR/$to_del/$db $BACKUPDIR/$db	# moving files keeps creation date
#    done
#	log "Kept db's from $to_del-$day"
#else
	rm -rf $BACKUPDIR/$to_del
	log "Deleted old: $BACKUPDIR/$to_del"
	count=0
	while [ $count -lt 3 ]
	do
	    count=$(($count+1))
	    #echo $count argmax # for test
	    check_space
	done
#fi
}

#pfs="95" # for test

function check_space {
    #pfs=$(($pfs-1)) # for test
    pfs=`df -h $BACKUPDIR | awk 'NR==2{print $5}' | cut -d% -f 1`
    #pfs="90"

    if [ $pfs -gt $maxp ] ;then
	log "There is $pfs% space used on $BACKUPDIR"
	    if [ $del_en = "yes" ] ; then
		del_old_files
	    else
		log "No free space and del_en=$del_en so we abort here and send mail to $email"
		mail -s "Daily backup of $COMPUTER `date +'%F'`" "$email" < $tmpdir/maildata
	    exit
	    fi
    else
	log "Percent used space $pfs% on $BACKUPDIR ok."
    fi
}

function db_back {
    #Replace / with _ in dir name => filename
    #DIR_NAME=`echo "$DIRECTORIES" | awk '{gsub("/", "_", $0); print}'`

    ### All db's check and correct any errors found

    log "Starting automatic repair and optimize for all databases..."
    mysqlcheck -u$dbuser -p$dbpassword --all-databases --optimize --auto-repair --silent 2>&1
    ### Starting database dumps
    for i in `mysql -u$dbuser -p$dbpassword -Bse 'show databases'`; do
	log "Starting mysqldump $i"
	`mysqldump -u$dbuser -p$dbpassword $i --allow-keywords --comments=false --add-drop-table > $tmpdir/db-$i-$FDATE.sql`
	$TAR $ARG $BACKUPDIR/$MDATE/db-$i-$FDATE.tar.bz2 -C $tmpdir db-$i-$FDATE.sql
	rm -rf $tmpdir/db-$i-$FDATE.sql
	log "Dump OK. $i database saved OK!"
    done
}


#############
### START ###
#############
    rm -f $tmpdir/maildata
    if [ -d $BACKUPDIR ] ; then
	check_space
	else
	    mkdir $BACKUPDIR
	log1="$acum - `basename $0` - First run: primary dir $BACKUPDIR created."
        log "First run: primary dir $BACKUPDIR created."
    fi
check_mdir
check_tempdir
rm -rf $tmpdir/excluded
for a in `echo $EXCLUDED` ; do
exfile=`echo -e $a >> $tmpdir/excluded`
done
#exit
db_back

for i in `echo $DIRECTORIES` ; do
    XX=`echo $i | awk '{gsub("/", "_", $0); print}'`
    YX=`echo $i | awk '{print $1}'`
    fb=`ls $BACKUPDIR | grep ^full$XX-`
	if [ -z $fb ] ; then
	    log "No full backup found for $YX. Full backup now!"
	    echo > $tmpdir/full-backup$XX.lck
	    $TAR $ARG $BACKUPDIR/full$XX-$FDATE.tar.bz2 $YX -X $tmpdir/excluded
	    log "Backup of $YX done."
	fi

	# Monthly full backup
	if [ $DOM = "01" ] ; then
	    log "Starting full monthly backup for: $YX"
	    $TAR $ARG $BACKUPDIR/full$XX-$FDATE.tar.bz2 $YX -X $tmpdir/excluded
	    log "Full monthly backup for $YX done."
	else
	    # If it's not the first day of the month we make incremental backup
	    if [ ! -e $tmpdir/full-backup$XX.lck ] ; then
		log "Starting daily backup for: $YX"
		NEWER="--newer $FDATE"
		$TAR $NEWER $ARG $BACKUPDIR/$MDATE/i$XX-$FDATE.tar.bz2 $YX -X $tmpdir/excluded
		log "Daily backup for $YX done."
	    else
	    log "Lock file for $YX full backup exists!"
	    fi
	fi
    # Clean full backup directory lock file
    rm -rf $tmpdir/full-backup$XX.lck
done

#Clean temp dir
rm -rf $tmpdir/excluded
# End of script
log "All backup jobs done. Exiting script!"
}

restore () {

del_res ()
{
    # We now need to remove the newer files created after the restored backup date.
    to_rem=`find $path/$2 -newer $tmpdir/dateend`
    echo -en "\n$headline\n    For a clean backup restored at $3 we need now to delete the files\ncreated after the backup date.\n    If exists, a list of files to be deleted follows:\n\n"
        for a in $to_rem ; do
	    echo -e "To be removed: $a"
        done
    echo -en "\nPlease input \"yes\" to delete those files, if they exist, and press [ENTER]: "
    read del
	if [[ "$del" = "yes" ]] ; then
	    for a in $to_rem ; do
		rm -rf $a
	    done
		echo -en "All restore jobs done!\nDir $2 restored to date $3!\n"
	exit
	fi
}

if [ -z "$4" ] ; then
    path="/"
else
    path=$4					# this is the path where to extract the files
fi

RDATE=$3
DOM=`echo $RDATE | cut -d "-" -f3`		# Date of the Month eg. 27
MDATE=`echo $RDATE | cut -d "-" -f2`
YDATE=`echo $RDATE | cut -d "-" -f1`

type=$1
dir=`echo $2 | awk '{gsub("/", "_", $0); print}'`

if [ -z "$3" ] ; then
    echo -e "$usage"
    exit
fi

# poor date input verification: ${#RDATE} is 10 for a correct date 2009-01-30
# find the first possible restore date=day
year=`ls -ctF $BACKUPDIR | grep -v ^log/ | tail -n 1 | cut -d "-" -f 2`
md=`ls -ctF $BACKUPDIR | grep -v ^log/ | tail -n 1 | cut -d "-" -f 3`
day=`ls -ctF $BACKUPDIR | grep -v ^log/ | tail -n 1 | cut -d "-" -f 4 | cut -d "." -f 1`
resdate=$year$md$day

dh="1234"
err=`touch -t $YDATE$MDATE$DOM$dh $tmpdir/datestart 2>&1`

if [ -n "$err" ] & [ ${#RDATE} != 10 ] ; then
    #echo "err = $err"
    echo -e "$usage"
    echo -e "Invalid date format. Correct YYYY-MM-DD. Ex.: 2009-01-14\n"
    exit
fi

# check to see if user inputs date in future
TD=`date +%s` # today in epoch
ID=`date --date "$RDATE" +%s` # input date in epoch
RD=`date --date "$resdate" +%s` # first backup date in epoch

if [ "$ID" -ge "$TD" ] ; then
    echo -e "$usage"
    echo -e "Invalid date format. Date supplied $RDATE is in the future!\n"
    exit
fi

if [ "$RD" -gt "$ID" ] ; then
    echo -e "$usage"
    echo -e "Invalid date format. Date supplied $RDATE is before the first backup on $year-$md-$day!\n"
    exit
fi


#echo "Checking if path dir exist: $path"
if [ $type = "dir" ] ; then
	# echo $dir and $path
	if [ -d $path ] ; then
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

if [[ "$ok" = "yes" ]] ; then
	if [[ "$1" == "dir" ]] ; then
		if [[ "$2" == "all" ]] ; then
		    echo -en "\nExtracting all dir's backup from date $3 to $path:\n"
		    sleep 5 # We wait 5 secs for the user to see what's happening.
		else
		    # We suppose the user uses /dir
		    if [[ "$DIRECTORIES all" =~ "$2" ]] ; then
			echo -en "\nTrying to restore $2 dir's backup from date $3 to $path:\n\n"
			# we say "trying" because if the requested dir is "al" it matches!
			sleep 5
		    fi
		fi
	elif [[ "$1" == "db" ]] ; then
		if [[ "$2" == "all" ]] ; then
		    echo -en "\nRestoring all mysql databases from date $3 to local server:\n"
		    sleep 5
		else
		    if [[ "$dblist" =~ "$2" ]] ; then
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
touch -t $YDATE$MDATE$dst $tmpdir/datestart 2>&1
touch -t $YDATE$MDATE$DOM$hm $tmpdir/dateend 2>&1
if [ $type = "dir" ] ; then
    if [[ "$DIRECTORIES all" =~ "$2" ]] ; then
	if [ $dir = "all" ] ; then
	    farh=`find $BACKUPDIR -maxdepth 1 -type f -newer $tmpdir/datestart -a ! -newer $tmpdir/dateend | sed 's_.*/__' | grep ^full_`
	    arh=`find $BACKUPDIR/$YDATE-$MDATE -maxdepth 1 -type f -newer $tmpdir/datestart -a ! -newer $tmpdir/dateend | sed 's_.*/__' | grep -v ^db-`
	    # echo farh este $farh
	    # echo arh este $arh
	else
	    farh=`find $BACKUPDIR -maxdepth 1 -type f -newer $tmpdir/datestart -a ! -newer $tmpdir/dateend | sed 's_.*/__' | grep $dir | grep ^full_`
	    # echo farh e $farh
	    arh=`find $BACKUPDIR/$YDATE-$MDATE -maxdepth 1 -type f -newer $tmpdir/datestart -a ! -newer $tmpdir/dateend | sed 's_.*/__' | grep $dir | grep -v ^db-`
	    # echo arh e $arh
	fi
	for f in $farh ; do
	    echo -en "\tExtracting $f...\n\n"
	    $TAR $EARG $BACKUPDIR/$f -C $path &>/dev/null
	    # if the day is 01 the the full backup is recovered so we need to clean newer files created after the backup date.
	    if [ $DOM = "01" ] ; then
	    del_res $path $2 $3 $tmpdir
	    fi
	done
	  for i in $arh ; do
	    echo -en "\tExtracting $i...\n\n"
	    $TAR $EARG $BACKUPDIR/$YDATE-$MDATE/$i -C $path &>/dev/null
	  done
	    del_res $path $2 $3 $tmpdir
    else
	mesaj="Invalid directory to restore!"
    fi
elif [ "$type" = "db" ] ; then
	db=$2
	# here we build the db list to restore from the files we backed up before in the day requested
	dblist=`find  $BACKUPDIR/$YDATE-$MDATE -maxdepth 1 -type f | sed 's_.*/__' | grep ^db- | grep $YDATE-$MDATE-$DOM | cut -d "-" -f2`
	dblist="$dblist all"
	#echo $dblist
    for d in $dblist ; do
	if [ "$d" == "$2" ] ; then
    	    if [ "$db" = "all" ] ; then
		# get db list from backup and restore all db's
		arh=`find  $BACKUPDIR/$YDATE-$MDATE -maxdepth 1 -type f | sed 's_.*/__' | grep ^db- | grep $YDATE-$MDATE-$DOM`
	    else
		arh=`find  $BACKUPDIR/$YDATE-$MDATE -maxdepth 1 -type f | sed 's_.*/__' | grep ^db- | grep $db- | grep $YDATE-$MDATE-$DOM`
	    fi
	    for i in $arh ; do
		rdb=`echo $i | cut -d "-" -f2`
		mysql --user="$dbuser" --password="$dbpassword" --execute "CREATE DATABASE IF NOT EXISTS $rdb;"
		$BZIP2 -dc $BACKUPDIR/$YDATE-$MDATE/$i | $TAR -xvO | mysql --user="$dbuser" --password="$dbpassword" --database=$rdb
	    done
		echo -en "All restore jobs done!\nDatabase $2 restored to date $3!\n"
	fi
    done

    if [ -z "$rdb" ] ; then
	mesaj="Invalid database to restore!"
    fi


else
    echo -e "$usage"
    mesaj="Invalid type specified"
fi

if [ -n "$mesaj" ] ; then
    echo -e "$usage"
    echo -en "\t\t###\t$mesaj\t###\n\n"
fi

# Send accumulated maildata an cleanup
mail -s "Daily backup of $COMPUTER `date +'%F'`" "$email" < $tmpdir/maildata
rm -rf $tmpdir/datestart
rm -rf $tmpdir/dateend
rm -rf $tmpdir/excluded
rm -rf $tmpdir/maildata

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
