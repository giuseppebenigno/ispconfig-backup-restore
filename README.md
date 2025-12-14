# Backup and Restore Script

A backup and restore script for databases and directories.

## Description

The state of development is "It works for me"!
So don't blame me if anything bad will happen to you or to your computer
if you use this script.
I've done my best to make myself understood if you read on.

**Detailed Description**

*   Full dir, mysql and incremental backup script
*   Full and incremental restore script
*   It's meant to use minimum resources and space and keep a loooong backup.
*   I've tried to make as more checks as possible but I can't beat "smart" users.
*   Weird things can happen if your backup dirs includes the "-" or "_" chars.
*   Those chars are used by this script and files formed by the script.

## Backup Usage

**Important!!!** Make sure your system has a correct date. Suggestion: use ntp.

Backup is not meant to be interactive, it's meant to be run daily from cron.
That's why the log for backup is kept in logdir `$LOG_FILE`.

*   On the first time of the month a permanent full backup is made.
*   The rest of the time an incremental backup is made, by date.
*   Databases are at full always and the script makes an automatic repair and optimizes the databases before the backup.

### Warnings

> [!WARNING]
> If you set the `DELETE_OLD` variable to "yes" the script will delete the old backups to make room for the new ones.

All incremental backups and databases for a month will be deleted if space is less than the maximum percent of used space `MAX_PERCENT_OF_USED_SPACE`.

You need to take care to not enter in an endless loop if you set `DELETE_OLD="yes"`
The loop can happen if deleted files form `$BACKUP_DIR` don't decrease the percent of used space.

The script check for some dirs and files and it's supposed to be run as root.
The script is supposed to be run daily from cron at night like:
`40 3 * * * /usr/local/bin/backup-restore.sh 1>/dev/null 2>/dev/null`

This scripts verifies and corrects all errors found in ALL mysql databases.
The script also makes full backups of ALL mysql databases every time it's run.

## Restore Usage

Restore is meant to be little interactive, the messages are on standard output.
Directories are restored verbose with tar by default.

Last minute of the day `$LAST_MINUTE_OF_THE_DAY` is set to 2359 but the backup is started at 03:40 so this should be set AFTER the backup has ended! At 23:59 of the backup day we can have many files modified from the 03:40. The not so perfect solution is to backup later in the day (23:00) and hope the backup finishes until 23:59.
My server is still loaded on the 23:00, so I use 03:40 in cron and `LAST_MINUTE_OF_THE_DAY=2359` because a full backup last for more than 16 hours for tar.bz2.

For sure I will loose all files created between 03:40 and 23:59 of that day.
To prevent that I can restore files one day AFTER the day I want to restore and use `find --newer` to delete unwanted files.

### Directories

To restore dirs make sure you have the full backup from that month and use:

```bash
back-res dir /etc 2009-11-23 /
```

to restore the `/etc` dir from date 2009-11-23 to root.

```bash
back-res dir /etc 2009-11-23 /tmp
```

is used to restore the `/etc` dir to `/tmp`.

```bash
back-res dir all 2009-11-23 /
```

to restore all directories from date 2009-11-23 to root.

### Databases

To restore databases use:

```bash
back-res db mysql 2009-11-23
```

to restore the `mysql` database from date 2009-11-23 to local mysql server.

```bash
back-res db all 2009-11-23
```

to restore all databases from date 2009-11-23 to local mysql server.

Where 'dir' or 'db' to restore is one of the configured dirs or db's to backup, or 'all' to restore all dirs or db's.
Date format is full date, year sorted, YYYY-MM-DD, like 2009-01-30.
'path' is for dirs and is the path on which you want to extract the backup.
If the path to extract is not set, then the backup is extracted on /.
