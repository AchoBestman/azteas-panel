#!/bin/bash
set -euo pipefail

# ============================================================
# Restaure Piler depuis un snapshot restic (Backblaze B2)
# Usage : ./restore-from-b2.sh [SNAPSHOT_ID]
#         (par defaut : "latest")
#
# OPTIMISE POUR GRANDS VOLUMES :
# - piler_store (potentiellement des TB) restauré DIRECTEMENT
#   vers /mnt/storagebox/piler-store sans passer par /tmp
# - piler_etc et dump SQL (petits) passent par /tmp
#
# SECURITE ANTI-DUPLICATION :
# Refuse de restaurer si la base MySQL contient deja des donnees.
# Concu pour une restauration sur un systeme VIDE.
# ============================================================

cd "$(dirname "${BASH_SOURCE[0]}")/.."

SNAPSHOT="${1:-latest}"
LOG_FILE="/var/log/piler-restore.log"
set -a; source .env > /dev/null 2>&1; set +a

# Rediriger stdout et stderr vers le log ET le terminal
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "=== Debut restauration Piler (snapshot: $SNAPSHOT) ==="
log "Suivi en temps reel : tail -f $LOG_FILE"

echo "=== 1/5 : Verification anti-duplication ==="
EXISTING_COUNT=$(docker compose exec -T mysql mariadb -u piler -p"${MYSQL_PASSWORD}" piler \
    -N -e "SELECT COUNT(*) FROM metadata;" 2>/dev/null || echo "0")

if [ "${EXISTING_COUNT}" != "0" ]; then
    echo "ERREUR : la base contient deja ${EXISTING_COUNT} emails."
    echo "Ce script ne fait PAS de fusion."
    echo ""
    echo "Pour repartir de zero avec ce snapshot :"
    echo "  docker compose down -v"
    echo "  docker compose up -d"
    echo "  puis relance ce script"
    exit 1
fi

echo "Base vide confirmee, restauration en toute securite."
echo ""

echo "=== 2/5 : Restauration piler_store directement vers Hetzner Storage Box ==="
echo "    (aucun passage par /tmp — supporte les volumes de plusieurs TB)"
# Restaure directement au chemin original sans intermédiaire
restic restore "${SNAPSHOT}" \
    --target / \
    --include '/mnt/storagebox/piler-store'
echo "    piler_store restauré"

echo ""
echo "=== 3/5 : Restauration piler_etc (config, petite taille) ==="
RESTORE_TMP="/tmp/piler-restore-small-$(date +%s)"
mkdir -p "${RESTORE_TMP}"
restic restore "${SNAPSHOT}" \
    --target "${RESTORE_TMP}" \
    --include '/var/lib/docker/volumes/piler_piler_etc'

ETC_VOLUME_PATH=$(docker volume inspect piler_piler_etc --format '{{.Mountpoint}}')
rsync -a "${RESTORE_TMP}/var/lib/docker/volumes/piler_piler_etc/_data/" "${ETC_VOLUME_PATH}/"
echo "    piler_etc restauré"

echo ""
echo "=== 4/5 : Restauration de la base MySQL ==="
restic restore "${SNAPSHOT}" \
    --target "${RESTORE_TMP}" \
    --include '/opt/azteas-panel/piler/backup/tmp'

DUMP_FILE=$(find "${RESTORE_TMP}/opt/azteas-panel/piler/backup/tmp" -name "piler_db_*.sql" | sort | tail -1)
if [ -z "${DUMP_FILE}" ]; then
    echo "ERREUR : aucun dump SQL trouve dans le snapshot."
    rm -rf "${RESTORE_TMP}"
    exit 1
fi
docker compose exec -T mysql mariadb -u piler -p"${MYSQL_PASSWORD}" piler < "${DUMP_FILE}"
echo "    Base MySQL restaurée"

echo ""
echo "=== 5/5 : Nettoyage et redemarrage ==="
rm -rf "${RESTORE_TMP}"
docker compose restart piler manticore

echo ""
echo "Restauration terminee."
echo "Verifie : docker compose exec mysql mariadb -u piler -p'MOT_DE_PASSE' piler -e 'SELECT COUNT(*) FROM metadata;'"
echo "Relance aussi : sudo bash fix-piler-config.sh"
