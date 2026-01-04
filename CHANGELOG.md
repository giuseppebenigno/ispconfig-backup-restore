# Changelog

## version 0.17.0 - 2026-01-04 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Renamed original script to `backup-restore-gz.sh` to reflect that it only uses gz/pigz compression (bzip2 removed)
- Updated `MAX_PERCENT_OF_USED_SPACE` threshold for backup maintenance

## version 0.16.4 - 2025-12-14 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Added `backup-restore-zstd.sh`: new script using zstd compression and parallel processing (80% of cores)
- Refactor: Moved usage/help text to a dedicated function in both scripts for cleaner code
- Added `-h`/`--help` and `-v`/`--version` flags to both scripts

## version 0.16.3 - 2025-12-14 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Improved Logging: Added detailed storage stats (Full vs Incremental/DB sizes), execution duration, and available disk space to the final log/email report
- Fix: Excluded 'information_schema' and 'performance_schema' from database backups to prevent 'Access denied' errors

## version 0.16.1 - 2025-12-14 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Critical Fix: Added /var/backup-restore to excluded paths to prevent recursion loop
- Refactored: Split BACKUP_DIR into BACKUP_ROOT_DIR and BACKUP_DIR to ensure the root backup path is always excluded automatically

## version 0.16.0 - 2025-12-14 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Changed compression: uses 'pigz' if available (fast, multicore) or fallback to 'gzip'
- Changed backup file extension to .tar.gz (was .tar.bz2)
- Updated restore logic to auto-detect compression format (fully backward compatible with .tar.bz2)

## version 0.15.0 - 2025-12-14 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Made list of services to stop before reboot configurable (SERVICES_TO_STOP array)
- Added check for active services before stopping them (`systemctl is-active`)

## version 0.14.1 - 2025-12-14 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Code style: Fixed indentation in backup loop logic

## version 0.14.0 - 2025-12-14 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Simplified resource limiting logic: removed manual pause/resume via signals
- Replaced custom limiting with standard 'ionice -c3' (Idle) and 'nice -n 19'
- Improved readability and safety by removing complex process management code

## version 0.13.0 - 2025-12-14 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Refactored directory iteration logic to use native Bash globbing instead of ls parsing
- Improved robustness for filenames with spaces
- Removed redundant checks for "." and ".."

## version 0.12.0 - 2025-12-14 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- If backup file exists, go to backup next file
- Added BACKUP_DB variable
- Moved CHANGELOG and documentation to separate files (CHANGELOG.md, README.md)
- Renamed script from back-res.sh to backup-restore.sh

## version 0.11.0 - 2021-07-12 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Get DB user from ISPC config file
- Added pause after every directory compression
- Use ".part" suffix for directory backup temporary files
  If the process is interrupted you will know which file is incomplete
- Added a maximum time for directory compression to run
- Added a time for intervals within a compression
- Added total running time of backup in log file
- Added nice 19 to all commands
- Added reboot on finish option

## version 0.10.0 - 2021-04-24 (by Giuseppe Benigno <giuseppe.benigno AT gmail.com>)
- Changed mysql import command for import stored functions too
- Changed variable names for more readability
- Change compress command line for compatibility with tar new version
- Change the day of full backup. Now the full backup will be performed whenever there is no one for the current month
- Change Log file name in $BACKUP_DIR/log/backup-$FULL_DATE.log

## version 0.9.6 - 2014-02-04 (by Yavuz Aydin - Vrij Media)
- Changed mysql import routine to create database if it doesn't exist
- Changed code to import database

## version 0.9.5 - 2014-01-25 (by Yavuz Aydin - Vrij Media)
- Removed /var from DIRECTORIES
- Added code to add all subdirectories of /var excluding /var/www and /var/vmail to DIRECTORIES
- Added code to add /var/www excluding subdirectories of /var/www/clients, all subdirectories of /var/www/clients and all subdirectories of /var/vmail to DIRECTORIES
- Changed variable COMPUTER to take computername from hostname -f

## version 0.9.4 - 2010-09-13
- Small fix: - Corrected small bug replaced tar with $TAR in the recovery line of the databases. (The line: mysql -u$DB_USER -p$DB_PASSWORD $rdb <)
  Thanks goes to Nimarda and colo.

## version 0.9.3 - 2010-08-01
- Small fix: - Modified del_old_files function to remove "/" from the $to_del variable used to delete old files
- Removed from del_old_files function the section used to keep old databases (It's not working if there is no space left on device). Added in TODO section

## version 0.9.2 - 2010-04-18
- Always download the latest version here: http://www.eurosistems.ro/back-res
- Thanks or questions: http://www.howtoforge.com/forums/showthread.php?t=41609

Fixes:
- First run now does not gives errors (Thanks nokia80, Snake12, rudolfpietersma, HyperAtom, jmp51483, bseibenick, dipeshmehta, andypl and all others)
- Modified the log function to accept first time dir createin
- Modified the starting sequence to not check the free space if the primary backup directory does not exist
- If primary backup dir does not exist now it's created at the start
- Added a line to remove the maildata at the start if the user stops the script before finishing his jobs. This prevents the script to send incorect mails.
- Added link http://www.howtoforge.com/forums/showthread.php?t=41609 maybe some of the downloaders will visit the forum.
- Added first TODO

## beta version 0.9.1 - first public release last modified 2009-12-06
- moved to http://www.eurosistems.ro/back-res.0.9.1

## TODO:
- Add required files check (tar, bzip2, mail, etc.)
- Create a better del_old_files function (2010-08-01)
- If you need anything else I'll be happy to do it in my spare time if you ask here: http://www.howtoforge.com/forums/showthread.php?t=41609
