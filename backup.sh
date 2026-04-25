#!/bin/bash
set -e

# --- 1. INITIALIZATION ---
CONFIG_FILE=${1:-"backup.conf"}
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file '$CONFIG_FILE' not found!"
    exit 1
fi
source "$CONFIG_FILE"

# Setup variables
TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
TARGET_ROOT="${LOCAL_BACKUP_ROOT:-/mnt/backup}/$BACKUP_NAME"
TARGET_DIR="$TARGET_ROOT/$TIMESTAMP"
MARKER_FILE="$TARGET_ROOT/.done_$TODAY"

# Logging function
log_msg() {
    logger -t "BACKUP_ENGINE" "[$BACKUP_NAME] $1"
    echo "[$BACKUP_NAME] $1"
}

# --- 2. PRE-FLIGHT CHECKS ---
if [ -z "$BACKUP_NAME" ]; then
    echo "Error: BACKUP_NAME is not defined in config!"
    exit 1
fi

if [ -f "$MARKER_FILE" ]; then
    log_msg "INFO: Backup already completed for today. Skipping."
    exit 0
fi

mkdir -p "$TARGET_DIR"

# --- 3. PRE-PROCESSING ---
log_msg "START: Commencing backup process..."

# Stop systemd service if defined
if [[ -n "$PRE_STOP_SERVICE" ]]; then
    log_msg "PRE: Stopping service '$PRE_STOP_SERVICE' on remote host..."
    ssh "$NAS_USER@$NAS_IP" "sudo systemctl stop $PRE_STOP_SERVICE"
fi

# Run custom app command (e.g., enable maintenance mode)
if [[ -n "$PRE_APP_COMMAND" ]]; then
    log_msg "PRE: Executing remote application command..."
    ssh "$NAS_USER@$NAS_IP" "$PRE_APP_COMMAND"
fi

# Database Dump
if [[ -n "$DB_NAME" ]]; then
    log_msg "PRE: Exporting database '$DB_NAME'..."
    ssh "$NAS_USER@$NAS_IP" "mysqldump -u $DB_USER -p$DB_PASS $DB_NAME > /tmp/db_dump.sql"
    scp "$NAS_USER@$NAS_IP:/tmp/db_dump.sql" "$TARGET_DIR/database.sql"
    ssh "$NAS_USER@$NAS_IP" "rm /tmp/db_dump.sql"
fi

# --- 4. SYNC PHASE ---
for dir in "${SOURCE_DIRS[@]}"; do
    log_msg "SYNC: Transferring $dir..."
    rsync -avz -e ssh --rsync-path="sudo rsync" "$NAS_USER@$NAS_IP:$dir" "$TARGET_DIR/"
done

# --- 5. POST-PROCESSING ---

# Run custom app command (e.g., disable maintenance mode)
if [[ -n "$POST_APP_COMMAND" ]]; then
    log_msg "POST: Executing remote application command..."
    ssh "$NAS_USER@$NAS_IP" "$POST_APP_COMMAND"
fi

# Start systemd service if defined
if [[ -n "$POST_START_SERVICE" ]]; then
    log_msg "POST: Starting service '$POST_START_SERVICE' on remote host..."
    ssh "$NAS_USER@$NAS_IP" "sudo systemctl start $POST_START_SERVICE"
fi

# --- 6. RETENTION (ROTATION) ---
if [[ -n "$ROTATION_COUNT" ]]; then
    log_msg "CLEANUP: Checking retention policy (Keeping $ROTATION_COUNT copies)..."
    # List directories by time, skip the newest X, delete the rest
    ls -1dt "$TARGET_ROOT"/*/ 2>/dev/null | tail -n +$((ROTATION_COUNT + 1)) | xargs rm -rf || true
fi

touch "$MARKER_FILE"
log_msg "OK: Backup finished successfully."