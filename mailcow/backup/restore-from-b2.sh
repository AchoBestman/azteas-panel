#!/bin/bash
set -euo pipefail

# ============================================================
# Restaure Mailcow depuis un snapshot restic (Backblaze B2)
# Usage : ./restore-from-b2.sh [SNAPSHOT_ID]
#         (par défaut : "latest")
#
# SÉCURITÉ : conçu pour une restauration sur un système VIDE
# (nouvelle instance Mailcow fraîchement installée).
# Ne pas utiliser sur un Mailcow actif avec données.
#
# Pour une restauration longue (gros volume), utiliser :
#   bash restore-background.sh [SNAPSHOT_ID]
# ============================================================

MAILCOW_DIR="/opt/mailcow-dockerized"
SNAPSHOT="${1:-latest}"
LOG_FILE="/var/log/mailcow-restore.log"

set -a; source /opt/azteas-panel/mailcow/.env > /dev/null 2>&1; set +a

exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "=== Début restauration Mailcow (snapshot: $SNAPSHOT) ==="
log "Suivi en temps réel : tail -f $LOG_FILE"

log "=== 1/4 : Restauration du snapshot restic ==="
RESTORE_DIR="/tmp/mailcow-restore-$(date +%s)"
mkdir -p "$RESTORE_DIR"
restic restore "$SNAPSHOT" --target "$RESTORE_DIR" --tag mailcow-backup

log ""
log "=== 2/4 : Arrêt de Mailcow ==="
cd "$MAILCOW_DIR"
docker compose down

log ""
log "=== 3/4 : Restauration via le script officiel Mailcow ==="
MAILCOW_BACKUP_LOCATION="$RESTORE_DIR" \
"$MAILCOW_DIR/helper-scripts/backup_and_restore.sh" restore

log ""
log "=== 4/4 : Nettoyage et redémarrage ==="
rm -rf "$RESTORE_DIR"
docker compose up -d

log ""
log "=== Restauration terminée ==="
log "Vérifie les logs : docker compose logs -f"
