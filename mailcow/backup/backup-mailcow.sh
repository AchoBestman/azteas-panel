#!/bin/bash
set -euo pipefail

# ============================================================
# Script de backup Mailcow -> Backblaze B2 chiffré (restic)
# Ref: https://docs.mailcow.email/backup_restore/b_n_r-backup/
# ============================================================

MAILCOW_DIR="/opt/mailcow-dockerized"
BACKUP_TMP="/tmp/mailcow-backup-tmp"
LOG_FILE="/var/log/mailcow-backup.log"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
THREADS=$(( $(nproc) - 2 ))
THREADS=$(( THREADS > 1 ? THREADS : 1 ))

# Charger les variables sans les afficher
set -a; source /opt/azteas-panel/mailcow/.env > /dev/null 2>&1; set +a

log() {
    # Ne jamais passer de valeur de secret en argument de cette fonction
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_TMP"
log "=== Debut backup Mailcow ==="

# --- 1. Vérifier que le repository restic existe, sinon l'initialiser ---
if ! restic snapshots > /dev/null 2>&1; then
    log "Repository restic introuvable, initialisation..."
    restic init
fi

# --- 2. Dump Mailcow via le script officiel vers dossier temporaire ---
log "Dump Mailcow (vmail, crypt, redis, rspamd, postfix, mysql)..."
MAILCOW_BACKUP_LOCATION="$BACKUP_TMP" \
THREADS="$THREADS" \
"$MAILCOW_DIR/helper-scripts/backup_and_restore.sh" backup all

if [ -z "$(ls -A "$BACKUP_TMP")" ]; then
    log "ERREUR: le dump Mailcow est vide, backup interrompu."
    exit 1
fi

# --- 3. Envoi vers Backblaze B2 via restic ---
log "Envoi vers Backblaze B2 (restic)..."
restic backup "$BACKUP_TMP" \
    --tag mailcow-backup \
    --tag "$DATE"

# --- 4. Nettoyage local ---
rm -rf "$BACKUP_TMP"

# --- 5. Politique de rétention ---
# Garde : 7 backups quotidiens, 4 hebdomadaires, 6 mensuels
log "Application de la politique de rétention..."
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune \
    --tag mailcow-backup

# --- 6. Vérification d'intégrité hebdomadaire (dimanche) ---
if [ "$(date +%u)" -eq 7 ]; then
    log "Vérification d'intégrité hebdomadaire..."
    restic check
fi

log "=== Backup Mailcow terminé avec succès ==="
