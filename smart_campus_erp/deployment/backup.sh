#!/bin/bash
BACKUP_DIR="/opt/backups/smart_campus"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="smart_campus_db"
DB_USER="postgres"

mkdir -p $BACKUP_DIR

pg_dump -U $DB_USER $DB_NAME | gzip > \
    "$BACKUP_DIR/backup_$DATE.sql.gz"

# Keep only last 7 days of backups
find $BACKUP_DIR -name "backup_*.sql.gz" \
    -mtime +7 -delete

echo "Backup complete: backup_$DATE.sql.gz"
