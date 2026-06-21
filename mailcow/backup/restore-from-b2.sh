#!/bin/bash
set -euo pipefail

# ============================================================
# Restaure Mailcow depuis un snapshot restic (Backblaze B2)
# Usage : ./restore-from-b2.sh [SNAPSHOT_ID]
#         (par défaut : "latest")
#
# SÉCURITÉ : ce script est conçu pour une restauration sur
# un système VIDE (nouvelle instance Mailcow fraîchement
# installée). Ne pas utiliser sur un Mailcow actif avec données.
# ============================================================

MAILCOW_DIR="/opt/mailcow-dockerized"
SNAPSHOT="${1:-latest}"

set -a; source /opt/azteas-panel/mailcow/.env > /dev/null 2>&1; set +a

echo "=== 1/4 : Restauration du snapshot restic ==="
RESTORE_DIR="/tmp/mailcow-restore-$(date +%s)"
mkdir -p "$RESTORE_DIR"
restic restore "$SNAPSHOT" --target "$RESTORE_DIR" --tag mailcow-backup

echo ""
echo "=== 2/4 : Arrêt de Mailcow ==="
cd "$MAILCOW_DIR"
docker compose down

echo ""
echo "=== 3/4 : Restauration via le script officiel Mailcow ==="
MAILCOW_BACKUP_LOCATION="$RESTORE_DIR" \
"$MAILCOW_DIR/helper-scripts/backup_and_restore.sh" restore

echo ""
echo "=== 4/4 : Nettoyage et redémarrage ==="
rm -rf "$RESTORE_DIR"
docker compose up -d

echo ""
echo "Restauration terminée."
echo "Vérifie les logs : docker compose logs -f"
