#!/bin/bash
set -euo pipefail

# ============================================================
# Restaure Piler depuis un snapshot restic (Backblaze B2)
# Usage : ./restore-from-b2.sh [SNAPSHOT_ID]
#         (par defaut : "latest")
#
# SECURITE ANTI-DUPLICATION :
# Si la base MySQL contient deja des donnees (table metadata
# non vide), le script REFUSE de continuer. Ce script est concu
# pour une restauration sur un systeme VIDE (nouveau VPS, ou
# apres un "docker compose down -v"), pas pour fusionner avec
# un Piler deja actif.
# ============================================================

cd "$(dirname "${BASH_SOURCE[0]}")/.."

SNAPSHOT="${1:-latest}"
source .env

echo "=== 1/5 : Verification anti-duplication ==="
EXISTING_COUNT=$(docker compose exec -T mysql mariadb -u piler -p"${MYSQL_PASSWORD}" piler \
    -N -e "SELECT COUNT(*) FROM metadata;" 2>/dev/null || echo "0")

if [ "${EXISTING_COUNT}" != "0" ]; then
    echo "ERREUR : la base contient deja ${EXISTING_COUNT} emails."
    echo "Ce script ne fait PAS de fusion - il restaurerait par-dessus"
    echo "des donnees existantes et creerait des doublons ou des conflits."
    echo ""
    echo "Pour restaurer sur un systeme deja actif, contacte-moi pour"
    echo "une procedure de fusion manuelle au cas par cas."
    echo ""
    echo "Si tu veux VRAIMENT repartir de zero avec ce snapshot :"
    echo "  docker compose down -v"
    echo "  docker compose up -d"
    echo "  puis relance ce script"
    exit 1
fi

echo "Base vide confirmee, restauration en toute securite."
echo ""

echo "=== 2/5 : Restauration du snapshot restic vers un dossier temporaire ==="
RESTORE_DIR="/tmp/piler-restore-$(date +%s)"
mkdir -p "${RESTORE_DIR}"
restic restore "${SNAPSHOT}" --target "${RESTORE_DIR}"

echo ""
echo "=== 3/5 : Restauration des volumes Docker (piler_etc, piler_store) ==="
DOCKER_VOL_PATH=$(find "${RESTORE_DIR}/var/lib/docker/volumes/piler_piler_etc" -maxdepth 0 2>/dev/null)
if [ -z "${DOCKER_VOL_PATH}" ]; then
    echo "ERREUR : structure de dossier inattendue dans le snapshot."
    echo "Verifie manuellement le contenu de ${RESTORE_DIR}"
    exit 1
fi

ETC_VOLUME_PATH=$(docker volume inspect piler_piler_etc --format '{{.Mountpoint}}')
STORE_VOLUME_PATH=$(docker volume inspect piler_piler_store --format '{{.Mountpoint}}')

rsync -a "${RESTORE_DIR}/var/lib/docker/volumes/piler_piler_etc/_data/" "${ETC_VOLUME_PATH}/"
rsync -a "${RESTORE_DIR}/var/lib/docker/volumes/piler_piler_store/_data/" "${STORE_VOLUME_PATH}/"

echo ""
echo "=== 4/5 : Restauration de la base MySQL ==="
DUMP_FILE=$(find "${RESTORE_DIR}/opt/azteas-panel/piler/backup/tmp" -name "piler_db_*.sql" | sort | tail -1)
if [ -z "${DUMP_FILE}" ]; then
    echo "ERREUR : aucun dump SQL trouve dans le snapshot."
    exit 1
fi
docker compose exec -T mysql mariadb -u piler -p"${MYSQL_PASSWORD}" piler < "${DUMP_FILE}"

echo ""
echo "=== 5/5 : Nettoyage et redemarrage ==="
rm -rf "${RESTORE_DIR}"
docker compose restart piler manticore

echo ""
echo "Restauration terminee. Verifie :"
echo "  docker compose exec mysql mariadb -u piler -p'TON_MOT_DE_PASSE' piler -e 'SELECT COUNT(*) FROM metadata;'"
echo ""
echo "Pense aussi a relancer les correctifs connus :"
echo "  sudo bash fix-piler-config.sh"
