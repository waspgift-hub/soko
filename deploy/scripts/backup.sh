#!/bin/bash
# Soko Vibe - PostgreSQL Backup Script
# Run daily via cron: 0 2 * * * /opt/sokovibe/deploy/scripts/backup.sh

set -euo pipefail

# Configuration
BACKUP_DIR="/opt/sokovibe/backups"
CONTAINER_NAME="sokovibe-postgres"
DB_NAME="${POSTGRES_DB:-sokovibe}"
DB_USER="${POSTGRES_USER:-sokovibe}"
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/sokovibe_${DATE}_${TIME}.sql.gz"
RETENTION_DAYS=30

# Create backup directory
mkdir -p "${BACKUP_DIR}"

echo "[BACKUP] Starting backup: ${DATE} ${TIME}"

# Dump and compress
docker exec "${CONTAINER_NAME}" pg_dump \
  -U "${DB_USER}" \
  -d "${DB_NAME}" \
  --format=custom \
  --compress=9 \
  > "${BACKUP_FILE}"

# Verify backup
if [ ! -s "${BACKUP_FILE}" ]; then
  echo "[BACKUP] ERROR: Backup file is empty!"
  exit 1
fi

BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
echo "[BACKUP] Completed: ${BACKUP_FILE} (${BACKUP_SIZE})"

# Cleanup old backups
echo "[BACKUP] Cleaning backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "sokovibe_*.sql.gz" -mtime +${RETENTION_DAYS} -delete

# Upload to R2 (if configured)
if command -v aws &> /dev/null && [ -n "${R2_BUCKET_BACKUPS:-}" ]; then
  echo "[BACKUP] Uploading to R2..."
  aws s3 cp "${BACKUP_FILE}" \
    "s3://${R2_BUCKET_BACKUPS}/postgres/${DATE}/$(basename ${BACKUP_FILE})" \
    --endpoint-url "https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" \
    --region auto
  echo "[BACKUP] R2 upload complete"
fi

echo "[BACKUP] Done"
