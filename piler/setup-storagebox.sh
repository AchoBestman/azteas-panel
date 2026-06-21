#!/bin/bash
set -euo pipefail

# ============================================================
# Configure le montage CIFS du Hetzner Storage Box pour piler_store
# A executer sur le VPS, en root/sudo
#
# Etapes :
#   1. Installe cifs-utils
#   2. Genere le fichier de credentials systeme (/etc/cifs-credentials-piler)
#   3. Cree le point de montage et le monte
#   4. Configure le montage automatique au demarrage (systemd mount unit)
#   5. Migre les donnees existantes du volume Docker local vers le Storage Box
#   6. Redemarre Piler pour qu'il utilise le nouveau point de montage
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOUNT_POINT="/mnt/storagebox"
STORE_SUBDIR="${MOUNT_POINT}/piler-store"
CRED_FILE="/etc/cifs-credentials-piler"

echo "[1/6] Installation de cifs-utils..."
apt-get update -qq
apt-get install -y cifs-utils winbind

echo "[2/6] Chargement de la configuration centrale (.env)..."
source "${SCRIPT_DIR}/../.env"

cat > "$CRED_FILE" << EOF
username=${STORAGEBOX_USERNAME}
password=${STORAGEBOX_PASSWORD}
EOF
chmod 600 "$CRED_FILE"
chown root:root "$CRED_FILE"

echo "[3/6] Creation du point de montage..."
mkdir -p "$MOUNT_POINT"

echo "[4/6] Note : permissions via file_mode/dir_mode (pas uid/gid)..."
# uid=/gid= et iocharset=utf8 declenchent un bug connu de cifs-utils sur ce
# systeme (mount error(79): Can not access a needed shared library).
# On utilise des permissions de fichiers ouvertes a la place, sans danger
# ici car l'acces au partage est deja protege par les identifiants CIFS.

echo "[5/6] Configuration du montage permanent (systemd mount unit)..."
UNIT_NAME=$(systemd-escape -p --suffix=mount "$MOUNT_POINT")

cat > "/etc/systemd/system/${UNIT_NAME}" << EOF
[Unit]
Description=Montage CIFS Hetzner Storage Box pour Piler
After=network-online.target
Wants=network-online.target

[Mount]
What=//${STORAGEBOX_HOST}/${STORAGEBOX_SHARE}
Where=${MOUNT_POINT}
Type=cifs
Options=credentials=${CRED_FILE},file_mode=0777,dir_mode=0777,vers=3.0,_netdev,nofail

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$UNIT_NAME"

echo "Verification du montage :"
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "ERREUR : le montage CIFS a echoue. Le script s'arrete ici"
    echo "pour eviter de copier des donnees au mauvais endroit (disque local)."
    echo "Verifie : journalctl -xe -u $(systemd-escape -p --suffix=mount "$MOUNT_POINT")"
    exit 1
fi
df -h "$MOUNT_POINT"

echo "Creation du sous-dossier piler-store sur le Storage Box (si absent)..."
mkdir -p "$STORE_SUBDIR"

echo ""
echo "[6/6] Migration des donnees existantes vers le Storage Box..."
OLD_STORE_PATH=$(docker volume inspect piler_piler_store --format '{{ .Mountpoint }}' 2>/dev/null || echo "")

if [ -n "$OLD_STORE_PATH" ] && [ -d "$OLD_STORE_PATH" ]; then
    echo "Ancien volume trouve : ${OLD_STORE_PATH}"
    echo "Copie en cours (peut prendre du temps selon le volume existant)..."
    rsync -av --progress "${OLD_STORE_PATH}/" "${STORE_SUBDIR}/"
    echo "Migration terminee."
else
    echo "Aucun ancien volume local trouve (installation neuve), rien a migrer."
fi

echo ""
echo "Redemarrage de Piler avec le nouveau point de montage..."
cd "${SCRIPT_DIR}/.."
docker compose up -d

echo ""
echo "Termine. Verifie :"
echo "  docker compose ps piler"
echo "  docker compose exec piler ls -la /var/piler/store"
echo ""
echo "⚠️ Une fois confirme que tout fonctionne, tu peux supprimer l'ancien"
echo "   volume Docker local pour liberer l'espace disque :"
echo "   docker volume rm piler_piler_store"