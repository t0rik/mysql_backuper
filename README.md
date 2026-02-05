# MySQL Backup Script - Installation Guide

## Description
This script creates backups of all MySQL databases organized by day of week with automatic rotation (7-day retention).

## Features
- ✅ Backup all MySQL databases
- ✅ Organized by day of week (Monday, Tuesday, etc.)
- ✅ Automatic compression (gzip)
- ✅ Local folder storage
- ✅ Optional FTP upload
- ✅ Automatic cleanup of old backups (7 days)
- ✅ Detailed logging of all operations

## Installation

### 1. Copy the script to your server
```bash
sudo cp mysql_backup_en.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/mysql_backup_en.sh
```

### 2. Configure settings
Edit the file and specify your credentials:

```bash
sudo nano /usr/local/bin/mysql_backup_en.sh
```

**Required parameters:**
```bash
MYSQL_USER="root"                    # MySQL user
MYSQL_PASSWORD="your_mysql_password" # MySQL password
MYSQL_HOST="localhost"               # MySQL host
BACKUP_DIR="/var/backups/mysql"      # Backup directory
```

**Optional FTP parameters:**
```bash
USE_FTP="yes"                        # Uncomment to enable
FTP_HOST="ftp.example.com"
FTP_USER="ftpuser"
FTP_PASSWORD="ftppassword"
FTP_DIR="/backups/mysql"
```

### 3. Create directories
```bash
sudo mkdir -p /var/backups/mysql
sudo mkdir -p /var/log
sudo touch /var/log/mysql_backup.log
sudo chmod 755 /var/backups/mysql
sudo chmod 644 /var/log/mysql_backup.log
```

### 4. Test run
```bash
sudo /usr/local/bin/mysql_backup_en.sh
```

Check the log:
```bash
tail -f /var/log/mysql_backup.log
```

## Automatic Execution Setup (Cron)

### Daily backup at 2:00 AM
```bash
sudo crontab -e
```

Add this line:
```
0 2 * * * /usr/local/bin/mysql_backup_en.sh >> /var/log/mysql_backup.log 2>&1
```

### Other schedule options

**Every 6 hours:**
```
0 */6 * * * /usr/local/bin/mysql_backup_en.sh >> /var/log/mysql_backup.log 2>&1
```

**Twice daily (2:00 AM and 2:00 PM):**
```
0 2,14 * * * /usr/local/bin/mysql_backup_en.sh >> /var/log/mysql_backup.log 2>&1
```

**Weekdays only at 3:00 AM:**
```
0 3 * * 1-5 /usr/local/bin/mysql_backup_en.sh >> /var/log/mysql_backup.log 2>&1
```

## Directory Structure

```
/var/backups/mysql/
├── Monday/
│   ├── database1_20250205_020001.sql.gz
│   └── database2_20250205_020015.sql.gz
├── Tuesday/
│   ├── database1_20250206_020001.sql.gz
│   └── database2_20250206_020015.sql.gz
├── Wednesday/
...
└── Sunday/
```

Each day of the week has its own folder, old backups are automatically deleted after 7 days.

## Security

### Recommended: use .my.cnf for password storage

1. Create configuration file:
```bash
sudo nano /root/.my.cnf
```

2. Add content:
```ini
[client]
user=root
password=your_mysql_password
host=localhost
```

3. Protect the file:
```bash
sudo chmod 600 /root/.my.cnf
```

4. Modify the script (remove password from parameters):
```bash
# Instead of -p"$MYSQL_PASSWORD" just use commands without password
mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -e "SHOW DATABASES;"
mysqldump -h "$MYSQL_HOST" -u "$MYSQL_USER" ...
```

## Restore from Backup

### Restore a specific database:
```bash
gunzip < /var/backups/mysql/Monday/database_name_20250205_020001.sql.gz | mysql -u root -p database_name
```

### Or in two steps:
```bash
# 1. Decompress
gunzip /var/backups/mysql/Monday/database_name_20250205_020001.sql.gz

# 2. Restore
mysql -u root -p database_name < /var/backups/mysql/Monday/database_name_20250205_020001.sql
```

## Monitoring

### Check last backup:
```bash
tail -n 50 /var/log/mysql_backup.log
```

### Check backup sizes:
```bash
du -sh /var/backups/mysql/*
```

### List recent backups:
```bash
find /var/backups/mysql -name "*.sql.gz" -mtime -1 -ls
```

## Email Notification Setup

Add to cron for email reports:
```
0 2 * * * /usr/local/bin/mysql_backup_en.sh 2>&1 | mail -s "MySQL Backup Report" admin@example.com
```

Or modify the script by adding at the end of main() function:
```bash
# Send email report
echo "Backup completed. Success: $success, Failed: $failed" | \
    mail -s "MySQL Backup - $DATE" admin@example.com
```

## Requirements

- MySQL/MariaDB
- bash
- gzip
- ftp (optional, for FTP backups)
- lftp (optional, for advanced FTP operations)
- mailutils (optional, for email notifications)

## Install Additional Utilities

```bash
# Debian/Ubuntu
sudo apt-get install gzip ftp lftp mailutils

# CentOS/RHEL
sudo yum install gzip ftp lftp mailx
```

## Troubleshooting

### "Access denied" error
- Check MySQL user and password
- Ensure the user has backup privileges

### "Permission denied" error
- Check permissions on backup directory
- Run script as root or with sudo

### FTP not working
- Check ftp client installation
- Verify FTP server accessibility
- Consider using lftp for more reliable operation

## Laravel Support

If you're using Laravel, you can integrate backups via package:

```bash
composer require spatie/laravel-backup
php artisan vendor:publish --provider="Spatie\Backup\BackupServiceProvider"
```

This will give you more control and integration with your application.

## Advanced Version Features

The `mysql_backup_advanced_en.sh` script includes:

- **Better FTP support** via lftp (more reliable than standard ftp)
- **Disk space checking** before backup
- **Backup integrity verification** using gzip -t
- **Email notifications** with detailed reports
- **Better error handling** and reporting
- **Failed database tracking** in reports

To use the advanced version:
```bash
sudo cp mysql_backup_advanced_en.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/mysql_backup_advanced_en.sh
```

Enable email notifications by setting:
```bash
ENABLE_EMAIL="yes"
EMAIL_TO="admin@example.com"
```

## Best Practices

1. **Test restores regularly** - Don't trust backups you've never restored
2. **Monitor backup logs** - Set up alerts for failed backups
3. **Keep multiple backup locations** - Use both local and FTP/remote storage
4. **Verify disk space** - Ensure sufficient space for backups
5. **Secure credentials** - Use .my.cnf or environment variables instead of hardcoded passwords
6. **Document your process** - Keep notes on restore procedures
7. **Test on non-production** - Always test scripts on dev environment first

## Support

For issues or improvements:
- Check the log file: `/var/log/mysql_backup.log`
- Verify MySQL credentials and permissions
- Ensure all required utilities are installed
- Test individual commands manually to isolate issues
