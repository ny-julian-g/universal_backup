#!/bin/bash
set -e

# --- 1. INITIALISIERUNG ---
CONFIG_FILE=${1:-"backup.conf"}
[ -f "$CONFIG_FILE" ] || { echo "Fehler: $CONFIG_FILE nicht gefunden!"; exit 1; }
source "$CONFIG_FILE"

TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
TARGET_ROOT="${LOCAL_BACKUP_ROOT:-/mnt/backup}/$BACKUP_NAME"
TARGET_DIR="$TARGET_ROOT/$TIMESTAMP"

log_msg() {
    logger -t "BACKUP_FRAMEWORK" "[$BACKUP_NAME] $1"
    echo "[$BACKUP_NAME] $1"
}

# --- 2. VALIDIERUNG & PRÜFUNG ---
[ -z "$BACKUP_NAME" ] && { echo "BACKUP_NAME fehlt!"; exit 1; }
[ -f "$TARGET_ROOT/.done_$TODAY" ] && { log_msg "INFO: Heute bereits erledigt."; exit 0; }
mkdir -p "$TARGET_DIR"

# --- 3. PRE-PROCESSING (Vorbereitung) ---
log_msg "START: Backup-Prozess läuft..."

# Generischer Service-Stop
if [[ -n "$PRE_STOP_SERVICE" ]]; then
    log_msg "PRE: Stoppe Dienst $PRE_STOP_SERVICE..."
    ssh "$NAS_USER@$NAS_IP" "sudo systemctl stop $PRE_STOP_SERVICE"
fi

# Generischer App-Befehl (z.B. Nextcloud Maintenance Mode)
if [[ -n "$PRE_APP_COMMAND" ]]; then
    log_msg "PRE: Führe App-Befehl aus..."
    ssh "$NAS_USER@$NAS_IP" "$PRE_APP_COMMAND"
fi

# Generischer Datenbank-Export
if [[ -n "$DB_NAME" ]]; then
    log_msg "PRE: Exportiere Datenbank $DB_NAME..."
    ssh "$NAS_USER@$NAS_IP" "mysqldump -u $DB_USER -p$DB_PASS $DB_NAME > /tmp/db_dump.sql"
    scp "$NAS_USER@$NAS_IP:/tmp/db_dump.sql" "$TARGET_DIR/database.sql"
    ssh "$NAS_USER@$NAS_IP" "rm /tmp/db_dump.sql"
fi

# --- 4. SYNC (Datenübertragung) ---
for dir in "${SOURCE_DIRS[@]}"; do
    log_msg "SYNC: Kopiere $dir..."
    rsync -avz -e ssh --rsync-path="sudo rsync" "$NAS_USER@$NAS_IP:$dir" "$TARGET_DIR/"
done

# --- 5. POST-PROCESSING (Aufräumen/Starten) ---

# Generischer App-Befehl (z.B. Maintenance OFF)
if [[ -n "$POST_APP_COMMAND" ]]; then
    log_msg "POST: Führe App-Befehl aus..."
    ssh "$NAS_USER@$NAS_IP" "$POST_APP_COMMAND"
fi

# Generischer Service-Start
if [[ -n "$POST_START_SERVICE" ]]; then
    log_msg "POST: Starte Dienst $POST_START_SERVICE..."
    ssh "$NAS_USER@$NAS_IP" "sudo systemctl start $POST_START_SERVICE"
fi

# --- 6. ROTATION ---
if [[ -n "$ROTATION_COUNT" ]]; then
    log_msg "CLEANUP: Behalte $ROTATION_COUNT Backups..."
    ls -1dt "$TARGET_ROOT"/*/ 2>/dev/null | tail -n +$((ROTATION_COUNT + 1)) | xargs rm -rf || true
fi

touch "$TARGET_ROOT/.done_$TODAY"
log_msg "OK: Backup erfolgreich abgeschlossen."