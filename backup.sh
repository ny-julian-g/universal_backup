#!/bin/bash
set -e

# 1. CONFIG LADEN
CONFIG_FILE=${1:-"backup.conf"}
[ -f "$CONFIG_FILE" ] || { echo "Config $CONFIG_FILE fehlt!"; exit 1; }
source "$CONFIG_FILE"

# 2. VARIABLEN & LOGGING (Saubere Pfade!)
TODAY=$(date +%Y-%m-%d)
DATE_TIME=$(date +"%Y-%m-%d_%H-%M")
# Neuer Standard-Pfad: /mnt/backup/NAME/ZEITSTEMPEL
TARGET_ROOT="/mnt/backup/$BACKUP_NAME"
TARGET_DIR="$TARGET_ROOT/$DATE_TIME"
MARKER_FILE="$TARGET_ROOT/.done_$TODAY"

log_msg() {
    logger -t "BACKUP_$BACKUP_NAME" "[$1] $2"
    echo "[$1] $2"
}

# 3. PRÜFUNGEN
[ -f "$MARKER_FILE" ] && { log_msg "OK" "Heute bereits erledigt."; exit 0; }
mkdir -p "$TARGET_DIR"

# 4. ABLAUF
log_msg "INFO" "Start Backup: $BACKUP_NAME"

# A: Vorbereitung (Stop/Maintenance)
[[ -n "$STOP_SERVICE" ]] && ssh $NAS_USER@$NAS_IP "sudo systemctl stop $STOP_SERVICE"
[[ "$NEXTCLOUD_MODE" == "true" ]] && ssh $NAS_USER@$NAS_IP "sudo -u www-data php $NC_PATH/occ maintenance:mode --on"

# B: DB Dump
if [[ -n "$DB_NAME" ]]; then
    ssh $NAS_USER@$NAS_IP "mysqldump -u $DB_USER -p$DB_PASS $DB_NAME > /tmp/db.sql"
    scp $NAS_USER@$NAS_IP:/tmp/db.sql "$TARGET_DIR/db.sql"
    ssh $NAS_USER@$NAS_IP "rm /tmp/db.sql"
fi

# C: Rsync (LB3 Punkt c: Schleife über Array)
for dir in "${SOURCE_DIRS[@]}"; do
    rsync -avz -e ssh --rsync-path="sudo rsync" $NAS_USER@$NAS_IP:$dir "$TARGET_DIR/"
done

# D: Nachbereitung (Start/Maintenance off)
[[ -n "$STOP_SERVICE" ]] && ssh $NAS_USER@$NAS_IP "sudo systemctl start $STOP_SERVICE"
[[ "$NEXTCLOUD_MODE" == "true" ]] && ssh $NAS_USER@$NAS_IP "sudo -u www-data php $NC_PATH/occ maintenance:mode --off"

# E: ROTATION (Löscht alte Backups)
# Zählt Ordner im Verzeichnis. Wenn mehr als ROTATION_COUNT, lösche die ältesten.
if [[ -n "$ROTATION_COUNT" ]]; then
    log_msg "INFO" "Prüfe Rotation (Behalte $ROTATION_COUNT)..."
    # Listet nur Verzeichnisse auf, sortiert nach Zeit, schneidet die neuesten X ab
    ls -1dt "$TARGET_ROOT"/*/ 2>/dev/null | tail -n +$((ROTATION_COUNT + 1)) | xargs rm -rf || true
fi

touch "$MARKER_FILE"
log_msg "OK" "Backup $BACKUP_NAME abgeschlossen."
