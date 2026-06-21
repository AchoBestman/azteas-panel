#!/bin/bash
set -euo pipefail

# ============================================================
# Script de backup Piler -> stockage chiffre offsite (restic)
# ============================================================

PILER_DIR="/opt/azteas-panel/piler"
BACKUP_TMP="/opt/azteas-panel/piler/backup/tmp"
LOG_FILE="/var/log/piler-backup.log"
DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Charge la configuration centrale (RESTIC_REPOSITORY, RESTIC_PASSWORD, B2_*, etc.)
# 'set -a' exporte automatiquement toutes les variables chargees ensuite,
# necessaire pour que le processus 'restic' (enfant) puisse les lire.
set -a
source "${PILER_DIR}/.env"
set +a

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_TMP"
log "=== Debut backup Piler ==="

# --- 1. Verifier que le repository restic existe, sinon l'initialiser ---
if ! restic snapshots > /dev/null 2>&1; then
    log "Repository restic introuvable, initialisation..."
    restic init
fi

# --- 2. Dump MySQL (coherence des donnees, pas juste une copie du volume) ---
log "Dump de la base MySQL piler..."
docker exec piler_mysql sh -c 'exec mysqldump -u piler -p"$MYSQL_PASSWORD" piler' \
    > "${BACKUP_TMP}/piler_db_${DATE}.sql"

if [ ! -s "${BACKUP_TMP}/piler_db_${DATE}.sql" ]; then
    log "ERREUR: le dump MySQL est vide, backup interrompu pour eviter une sauvegarde corrompue."
    exit 1
fi

# --- 3. Backup des donnees (fichiers emails sur Storage Box + config locale) ---
log "Backup de piler_store (lecture reseau depuis Storage Box) et piler_etc..."

# On utilise le point de montage reel : piler_etc reste un volume Docker
# nomme, mais piler_store est desormais le montage CIFS Hetzner Storage Box
PILER_STORE_PATH="/mnt/storagebox/piler-store"
PILER_ETC_PATH=$(docker volume inspect piler_piler_etc --format '{{ .Mountpoint }}')

# --- 4. Envoi vers le stockage chiffre via restic ---
log "Envoi vers le repository restic distant..."
restic backup \
    "${BACKUP_TMP}/piler_db_${DATE}.sql" \
    "$PILER_STORE_PATH" \
    "$PILER_ETC_PATH" \
    --exclude '._*' \
    --exclude '.DS_Store' \
    --tag piler-backup \
    --tag "$DATE"

# --- 5. Nettoyage local du dump temporaire ---
rm -f "${BACKUP_TMP}/piler_db_${DATE}.sql"

# --- 6. Politique de retention ---
# Garde : 7 backups quotidiens, 4 hebdomadaires, 6 mensuels
log "Application de la politique de retention..."
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune

# --- 7. Verification d'integrite (a faire moins souvent, ex: 1x/semaine) ---
if [ "$(date +%u)" -eq 7 ]; then
    log "Verification d'integrite hebdomadaire (dimanche)..."
    restic check
fi

log "=== Backup termine avec succes ==="