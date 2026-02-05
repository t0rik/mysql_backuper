#!/bin/bash

#######################################
# MySQL Backup Script
# Creates backups of all MySQL databases
# with daily rotation (7 days retention)
#######################################

# === CONFIGURATION ===

# MySQL settings
MYSQL_USER="root"
MYSQL_PASSWORD="your_mysql_password"
MYSQL_HOST="localhost"

# Local storage (comment out if using FTP only)
BACKUP_DIR="/var/backups/mysql"

# FTP settings (uncomment to use)
# USE_FTP="yes"
# FTP_HOST="ftp.example.com"
# FTP_USER="ftpuser"
# FTP_PASSWORD="ftppassword"
# FTP_DIR="/backups/mysql"

# Retention period in days (default 7)
RETENTION_DAYS=7

# Date and day of week
DATE=$(date +%Y-%m-%d)
DAY_OF_WEEK=$(date +%A)  # Monday, Tuesday, etc.
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Log file
LOG_FILE="/var/log/mysql_backup.log"

# === FUNCTIONS ===

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Create backup directory
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_message "Created backup directory: $BACKUP_DIR"
    fi
    
    # Create subdirectory for day of week
    DAY_DIR="$BACKUP_DIR/$DAY_OF_WEEK"
    if [ ! -d "$DAY_DIR" ]; then
        mkdir -p "$DAY_DIR"
    fi
}

# Get list of all databases
get_databases() {
    mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW DATABASES;" \
        | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)"
}

# Create backup of a single database
backup_database() {
    local db=$1
    local backup_file="$DAY_DIR/${db}_${TIMESTAMP}.sql.gz"
    
    log_message "Starting backup of database: $db"
    
    # Create dump and compress it
    if mysqldump -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        "$db" | gzip > "$backup_file"; then
        
        local size=$(du -h "$backup_file" | cut -f1)
        log_message "✓ Backup of $db completed successfully. Size: $size"
        echo "$backup_file"
        return 0
    else
        log_message "✗ Error creating backup of $db"
        return 1
    fi
}

# Upload to FTP
upload_to_ftp() {
    local file=$1
    local filename=$(basename "$file")
    
    if [ "$USE_FTP" = "yes" ]; then
        log_message "Uploading to FTP: $filename"
        
        ftp -inv "$FTP_HOST" <<EOF
user $FTP_USER $FTP_PASSWORD
binary
cd $FTP_DIR/$DAY_OF_WEEK
put $file
bye
EOF
        
        if [ $? -eq 0 ]; then
            log_message "✓ File $filename uploaded to FTP"
        else
            log_message "✗ Error uploading $filename to FTP"
        fi
    fi
}

# Clean up old backups (older than RETENTION_DAYS)
cleanup_old_backups() {
    log_message "Cleaning up backups older than $RETENTION_DAYS days..."
    
    # Delete files older than specified number of days
    find "$BACKUP_DIR" -name "*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete
    
    # Remove empty directories
    find "$BACKUP_DIR" -type d -empty -delete
    
    log_message "Cleanup completed"
}

# Clean up old files on FTP
cleanup_ftp() {
    if [ "$USE_FTP" = "yes" ]; then
        log_message "Cleaning up old backups on FTP..."
        
        # This is a basic example. For more complex logic you need lftp or another client
        # that supports deletion by date
        
        log_message "FTP cleanup (requires manual configuration with lftp)"
    fi
}

# === MAIN PROCESS ===

main() {
    log_message "=========================================="
    log_message "Starting MySQL backup process"
    log_message "Day of week: $DAY_OF_WEEK"
    log_message "=========================================="
    
    # Create directories
    create_backup_dir
    
    # Get list of databases
    databases=$(get_databases)
    
    if [ -z "$databases" ]; then
        log_message "✗ No databases found for backup"
        exit 1
    fi
    
    # Counters
    total=0
    success=0
    failed=0
    
    # Backup each database
    for db in $databases; do
        ((total++))
        
        if backup_file=$(backup_database "$db"); then
            ((success++))
            
            # Upload to FTP if configured
            upload_to_ftp "$backup_file"
        else
            ((failed++))
        fi
    done
    
    # Clean up old backups
    cleanup_old_backups
    
    if [ "$USE_FTP" = "yes" ]; then
        cleanup_ftp
    fi
    
    # Final report
    log_message "=========================================="
    log_message "Backup completed"
    log_message "Total databases: $total"
    log_message "Successful: $success"
    log_message "Failed: $failed"
    log_message "=========================================="
    
    # Return error code if there were failed backups
    if [ $failed -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main
