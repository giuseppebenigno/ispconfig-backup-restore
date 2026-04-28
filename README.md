# Backup and Restore Script

A robust backup and restore system for ISPConfig (databases and directories) with support for Gzip and Zstd compression.

## Features

- **SHA256 Integrity Verification (v0.26.0+)**: Automatically generates `.sha256` checksum files for every backup for post-backup validation.
- **Pre-flight Tool Verification (v0.26.0+)**: Automatically checks for all required system tools (`tar`, `mysqldump`, `sha256sum`, etc.) before execution.
- **Robust Resource Cleanup (v0.26.0+)**: Uses an exit trap to ensure all temporary files are removed, even if the script is interrupted or crashes.
- **Improved Clarity (v0.26.0+)**: Redundant category extensions have been removed. Filenames now only show the compression format (e.g., `.tar.gz`), as the category is already clear from the directory structure.
- **Self-Contained Monthly Backups**: All data (files, databases, and logs) for a month are grouped in a `YYYY-MM` directory.
- **Incremental & Full Backups**: Automatic full monthly backup followed by daily incremental updates.
- **Split Backups**: Support for splitting large backup files into manageable parts.
- **Automatic Exclusions**: Skips `**/tmp/*` (Maildir) and common socket/lock files.
- **Email Notifications**: Alerts sent at the start and end of the backup process.
- **Database Optimization**: Automatic repair and optimization of all MySQL databases before dumping.
- **Compression**: Choose between `gzip` or `zstd` versions.
- **Parallel Processing**: Automatically uses 4/5 of available CPU cores for `zstd` and `gzip` (only if `pigz` is installed). Regular `gzip` remains single-threaded.
- **Duplicate Prevention**: Automatically skips backups if they already exist for the current day.
- **Improved Reliability**: Tolerates non-fatal `tar` warnings (Exit Code 1) and automatically excludes transient files (Maildir tmp).
- **Low System Impact**: Runs with lowest CPU priority (`nice -n 19`) and Idle I/O priority (`ionice -c3`) to ensure the server remains responsive during backups.
- **Flexible Options**: Granular toggles for `BACKUP_DB`, `BACKUP_WEB`, `BACKUP_MAIL`, and `BACKUP_SYSTEM`.
- **Selective Backup (-o/--only)**: Run only specific components from the command line (e.g., `--only db,mail`).
- **Per-Resource Isolation (v0.25.0+)**: Groups all backups for a single resource (website, DB, or mail) into its own subfolder.
- **Granular Portability**: Easily extract and deliver backups for a single site or database to clients without searching through hundreds of files.
- **Improved Organization**: Drastically reduced clutter in monthly directories by categorizing and nesting backups.
- **Granular Control**: Precision toggles for selective backups of databases, websites, mail, or system files.

## Backup Categories

The script categorizes backups into four main groups, which can be toggled via the `BACKUP_*` variables:

| Category     | Source Paths    | Description                                                                            |
| :----------- | :-------------- | :------------------------------------------------------------------------------------- |
| **`DB`**     | MySQL/MariaDB   | All databases except `information_schema` and `performance_schema`.                    |
| **`WEB`**    | `/var/www`      | Global files in `/var/www` and all ISPConfig sites in `/var/www/clients/clientN/webM`. |
| **`MAIL`**   | `/var/vmail`    | All mailboxes, domains, and mail configurations.                                       |
| **`SYSTEM`** | `/etc` & `/var` | System configurations and general `/var` data (excluding web, mail, and backup root).  |

## Backup Compression Comparison

Based on a ~1TB sample dataset on **Intel(R) Xeon(R) CPU E3-1275 v5 @ 3.60GHz** (4 cores, 8 threads).

| Format | Threading | Est. Time | Est. Size | Performance Summary                              |
| :----- | :-------- | :-------- | :-------- | :----------------------------------------------- |
| bz2    | Single    | 17h 00m   | 51 GB     | High compression ratio, extremely slow.          |
| gzip   | Single    | 8h 15m    | 56 GB     | Legacy format, poor multi-core utilization.      |
| pigz   | Multi     | 3h 05m    | 55 GB     | Faster alternative to gzip using all CPU cores.  |
| zstd   | Multi     | 1h 25m    | 53 GB     | **Recommended.** Best balance of speed and size. |

## Directory Structure (Version 0.25.0+)

The script organizes backups into a clean, modular hierarchy:

```text
/var/backup-restore/<hostname>/
└── YYYY-MM/                          <-- Monthly Root
    ├── log/                          <-- Backup Logs
    │   └── backup-YYYY-MM-DD.log
    ├── db/                           <-- Database Category
    │   └── db_name/                  <-- Resource Folder
    │       ├── db_name-YYYY-MM-DD.tar.gz
    │       └── db_name-YYYY-MM-DD.tar.gz.sha256
    ├── web/                          <-- Website Category
    │   └── folder_name/              <-- Resource Folder
    │       ├── full-YYYY-MM-DD/      <-- Split Backup Directory
    │       │   ├── part-aa.tar.gz
    │       │   └── part-ab.tar.gz
    │       ├── full-YYYY-MM-DD.tar.gz.sha256
    │       ├── i-YYYY-MM-DD.tar.gz
    │       └── i-YYYY-MM-DD.tar.gz.sha256
    ├── mail/                         <-- Mail Category
    │   └── user_name/                <-- Resource Folder
    │       ├── full-YYYY-MM-DD.tar.gz
    │       ├── full-YYYY-MM-DD.tar.gz.sha256
    │       ├── i-YYYY-MM-DD.tar.gz
    │       └── i-YYYY-MM-DD.tar.gz.sha256
    └── system/                       <--- System Category
        └── sysfolder/                <-- Resource Folder
            ├── full-YYYY-MM-DD.tar.gz
            ├── full-YYYY-MM-DD.tar.gz.sha256
            ├── i-YYYY-MM-DD.tar.gz
            └── i-YYYY-MM-DD.tar.gz.sha256
```

## Backup Usage

Backup is designed to be non-interactive and run via cron.

1. **First run of the month**: A permanent full backup is created.
2. **Daily runs**: Incremental backups are created based on the date of the full backup.
3. **Space Management**: If `DELETE_OLD="yes"`, the script automatically deletes the oldest monthly directory when disk usage exceeds `MAX_PERCENT_OF_USED_SPACE`.

### Selective Backup

You can run individual backup tasks by passing the `-o` or `--only` flag:

```bash
# Run only database backup
./backup-restore-gz.sh --only db

# Run database and mail backups (comma separated)
./backup-restore-gz.sh -o db,mail

# Run all (shorthand for default behavior)
./backup-restore-gz.sh -o all
```

### Crontab Example

```cron
40 3 * * * /usr/local/bin/backup-restore-gz.sh 1>/dev/null 2>/dev/null
```

> [!WARNING]
> Ensure your system clock is accurate (use NTP). The incremental logic depends heavily on file modification times.

## Restore Usage

Restoration is semi-interactive.

### Directories

```bash
# Restore /etc from a specific date to root (/)
./backup-restore-gz.sh dir /etc 2026-02-07 /

# Restore to a specific temporary path
./backup-restore-gz.sh dir /etc 2026-02-07 /tmp/restore_test
```

### Databases

```bash
# Restore a single database
./backup-restore-gz.sh db my_database 2026-02-07

# Restore all databases from backup
./backup-restore-gz.sh db all 2026-02-07
```

## Manual Extraction

If you need to extract a backup manually without using the script, use the following commands.

### Single File Backups

**For Gzip (.tar.gz):**

```bash
tar -xzvf filename.web.tar.gz
```

**For Zstd (.tar.zst):**

```bash
tar --zstd -xvf filename.web.tar.zst
```

### Split Backups (Folders with part-aa, part-ab...)

If the backup was split, enter the folder and run:

**For Gzip (.tar.gz):**

```bash
cat part-* | tar -xzvf -
```

**For Zstd (.tar.zstd):**

```bash
cat part-* | tar --zstd -xvf -
```

### Manual Database Restore

To restore a database dump (which is a compressed `.tar.gz` or `.tar.zst` containing a `.sql` file):

**For Gzip:**

```bash
tar -xOzf db-name-date.sql.tar.gz | mysql -u user -p db_name
```

**For Zstd:**

```bash
tar --zstd -xOf db-name-date.sql.tar.zst | mysql -u user -p db_name
```

---

_Copyright (c) Giuseppe Benigno <giuseppe.benigno@gmail.com>_
