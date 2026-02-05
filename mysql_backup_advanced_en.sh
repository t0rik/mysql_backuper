#!/bin/bash

#######################################
# MySQL Backup Script (Advanced)
# With improved FTP support via lftp
#######################################

# === CONFIGURATION ===

MYSQL_USER="root"
MYSQL_PASSWORD="your_mysql_password"
MYSQL_HOST="localhost"

BACKUP_DIR="/var/backups/mysql"

# FTP using lftp (more reliable)
USE_FTP="no"
FTP_HOST="ftp.example.com"
FTP_USER="ftpuser"
FTP_PASSWORD="ftppassword"
FTP_DIR="/backups/mysql"
FTP_PORT="21"

RETENTION_DAYS=7
DATE=$(date +%Y-%m-%d)
DAY_OF_WEEK=$(date +%A)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/mysql_backup.log"

# Email notifications (optional)
ENABLE_EMAIL="no"
EMAIL_TO="admin@example.com"
EMAIL_SUBJECT="MySQL Backup Report - $DATE"

# === FUNCTIONS ===

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

send_email_notification() {
    local subject=$1
    local message=$2
    
    if [ "$ENABLE_EMAIL" = "yes" ]; then
        echo "$message" | mail -s "$subject" "$EMAIL_TO"
    fi
}

create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_message "Created backup directory: $BACKUP_DIR"
    fi
    
    DAY_DIR="$BACKUP_DIR/$DAY_OF_WEEK"
    if [ ! -d "$DAY_DIR" ]; then
        mkdir -p "$DAY_DIR"
    fi
}

get_databases() {
    mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW DATABASES;" \
        | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)"
}

backup_database() {
    local db=$1
    local backup_file="$DAY_DIR/${db}_${TIMESTAMP}.sql.gz"
    
    log_message "Starting backup of database: $db"
    
    if mysqldump -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --quick \
        --lock-tables=false \
        "$db" | gzip > "$backup_file"; then
        
        local size=$(du -h "$backup_file" | cut -f1)
        log_message "✓ Backup of $db completed successfully. Size: $size"
        echo "$backup_file"
        return 0
    else
        log_message "✗ Error creating backup of $db"
        rm -f "$backup_file" 2>/dev/null
        return 1
    fi
}

# Improved FTP upload using lftp
upload_to_ftp_lftp() {
    local file=$1
    local filename=$(basename "$file")
    
    if [ "$USE_FTP" = "yes" ]; then
        log_message "Uploading to FTP: $filename"
        
        # Check if lftp is installed
        if ! command -v lftp &> /dev/null; then
            log_message "✗ lftp not installed. Use: apt-get install lftp"
            return 1
        fi
        
        lftp -e "
            set ftp:ssl-allow no;
            set net:timeout 10;
            set net:max-retries 3;
            open -u $FTP_USER,$FTP_PASSWORD $FTP_HOST;
            mkdir -pf $FTP_DIR/$DAY_OF_WEEK;
            cd $FTP_DIR/$DAY_OF_WEEK;
            put $file;
            bye
        "
        
        if [ $? -eq 0 ]; then
            log_message "✓ File $filename uploaded to FTP"
            return 0
        else
            log_message "✗ Error uploading $filename to FTP"
            return 1
        fi
    fi
}

# Clean up old files on FTP via lftp
cleanup_ftp_lftp() {
    if [ "$USE_FTP" = "yes" ]; then
        log_message "Cleaning up old backups on FTP..."
        
        if ! command -v lftp &> /dev/null; then
            log_message "✗ lftp not installed"
            return 1
        fi
        
        # Delete files older than RETENTION_DAYS
        lftp -e "
            set ftp:ssl-allow no;
            open -u $FTP_USER,$FTP_PASSWORD $FTP_HOST;
            cd $FTP_DIR;
            find -d $RETENTION_DAYS -name '*.sql.gz' -exec rm {} \;
            bye
        "
        
        log_message "FTP cleanup completed"
    fi
}

cleanup_old_backups() {
    log_message "Cleaning up local backups older than $RETENTION_DAYS days..."
    
    local deleted_count=$(find "$BACKUP_DIR" -name "*.sql.gz" -type f -mtime +$RETENTION_DAYS | wc -l)
    find "$BACKUP_DIR" -name "*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_DIR" -type d -empty -delete
    
    log_message "Deleted $deleted_count old backups"
}

# Check available disk space
check_disk_space() {
    local required_space_mb=1000  # Minimum 1GB free space
    local available_space=$(df -m "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    
    if [ "$available_space" -lt "$required_space_mb" ]; then
        log_message "⚠ WARNING: Low disk space! Available: ${available_space}MB"
        send_email_notification "WARNING: Low space for backups" \
            "Only ${available_space}MB available on disk"
        return 1
    fi
    
    log_message "Available disk space: ${available_space}MB"
    return 0
}

# Verify backup integrity
verify_backup() {
    local backup_file=$1
    
    if [ -f "$backup_file" ]; then
        if gzip -t "$backup_file" 2>/dev/null; then
            log_message "✓ Integrity check of $backup_file: OK"
            return 0
        else
            log_message "✗ Integrity check of $backup_file: FAILED"
            return 1
        fi
    fi
    
    return 1
}

main() {
    log_message "=========================================="
    log_message "Starting MySQL backup process"
    log_message "Day of week: $DAY_OF_WEEK"
    log_message "=========================================="
    
    # Check disk space
    check_disk_space
    
    # Create directories
    create_backup_dir
    
    # Get list of databases
    databases=$(get_databases)
    
    if [ -z "$databases" ]; then
        log_message "✗ No databases found for backup"
        send_email_notification "MySQL Backup Error" "No databases found for backup"
        exit 1
    fi
    
    total=0
    success=0
    failed=0
    failed_dbs=""
    
    # Backup each database
    for db in $databases; do
        ((total++))
        
        if backup_file=$(backup_database "$db"); then
            # Verify integrity
            if verify_backup "$backup_file"; then
                ((success++))
                
                # Upload to FTP
                upload_to_ftp_lftp "$backup_file"
            else
                ((failed++))
                failed_dbs="$failed_dbs $db"
            fi
        else
            ((failed++))
            failed_dbs="$failed_dbs $db"
        fi
    done
    
    # Clean up old backups
    cleanup_old_backups
    cleanup_ftp_lftp
    
    # Final report
    log_message "=========================================="
    log_message "Backup completed"
    log_message "Total databases: $total"
    log_message "Successful: $success"
    log_message "Failed: $failed"
    
    if [ $failed -gt 0 ]; then
        log_message "Failed backups:$failed_dbs"
    fi
    
    log_message "=========================================="
    
    # Send email report
    if [ "$ENABLE_EMAIL" = "yes" ]; then
        local email_body="MySQL Backup Report
        
Date: $DATE
Day of week: $DAY_OF_WEEK

Total databases: $total
Successful backups: $success
Failed: $failed

Directory: $BACKUP_DIR/$DAY_OF_WEEK
"
        
        if [ $failed -gt 0 ]; then
            email_body="$email_body
Failed backups:$failed_dbs
"
            send_email_notification "ERROR: $EMAIL_SUBJECT" "$email_body"
        else
            send_email_notification "$EMAIL_SUBJECT" "$email_body"
        fi
    fi
    
    # Return error code if there were failed backups
    if [ $failed -gt 0 ]; then
        exit 1
    fi
}

main
