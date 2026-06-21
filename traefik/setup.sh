#!/bin/bash
set -euo pipefail

# ============================================================
# Setup Traefik sur le VPS
# CE SCRIPT S'EXECUTE SUR LE VPS : ssh mailcow
# cd /opt/azteas-panel/traefik && bash setup.sh
# ============================================================

TRAEFIK_DIR="/opt/azteas-panel/traefik"

echo "==> Setup Traefik"

# 1. Créer le fichier acme.json avec les bonnes permissions
touch "${TRAEFIK_DIR}/letsencrypt/acme.json" 2>/dev/null || true
mkdir -p "${TRAEFIK_DIR}/letsencrypt"
touch "${TRAEFIK_DIR}/letsencrypt/acme.json"
chmod 600 "${TRAEFIK_DIR}/letsencrypt/acme.json"
echo "    acme.json créé"

# 2. Générer le mot de passe dashboard
echo ""
echo "==> Création du compte dashboard Traefik"
read -p "    Nom d'utilisateur [admin]: " DASHBOARD_USER
DASHBOARD_USER="${DASHBOARD_USER:-admin}"

read -s -p "    Mot de passe : " DASHBOARD_PASSWORD
echo ""

if ! command -v htpasswd &>/dev/null; then
    echo "    Installation de apache2-utils pour htpasswd..."
    sudo apt-get install -y apache2-utils -q
fi

HASHED=$(htpasswd -nbB "$DASHBOARD_USER" "$DASHBOARD_PASSWORD")
# Echapper les $ pour docker-compose
HASHED_ESCAPED=$(echo "$HASHED" | sed 's/\$/\$\$/g')

# 3. Créer le .htpasswd pour Traefik (sans échappement)
echo "$HASHED" > "${TRAEFIK_DIR}/dynamic/.htpasswd"
chmod 600 "${TRAEFIK_DIR}/dynamic/.htpasswd"
echo "    .htpasswd créé"

# 4. Créer le .env
cat > "${TRAEFIK_DIR}/.env" << EOF
ACME_EMAIL=admin@azteas.com
TRAEFIK_DASHBOARD_AUTH=${HASHED_ESCAPED}
EOF
chmod 600 "${TRAEFIK_DIR}/.env"
echo "    .env créé"

echo ""
echo "==> Setup terminé. Pour démarrer Traefik :"
echo "    cd ${TRAEFIK_DIR} && docker compose up -d"
