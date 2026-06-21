#!/bin/bash
set -euo pipefail

# ============================================================
# Setup Traefik sur le VPS
# CE SCRIPT S'EXECUTE SUR LE VPS : ssh mailcow
# cd /opt/azteas-panel/traefik && bash setup.sh
#
# Idempotent : peut être relancé sans risque.
# Si .env et .htpasswd existent déjà, le script s'arrête
# sauf si on passe --force pour tout régénérer.
# ============================================================

TRAEFIK_DIR="/opt/azteas-panel/traefik"
FORCE="${1:-}"

echo "==> Setup Traefik"

# Vérifier si déjà configuré
ALREADY_CONFIGURED=false
if [ -f "${TRAEFIK_DIR}/.env" ] && [ -f "${TRAEFIK_DIR}/dynamic/.htpasswd" ]; then
    ALREADY_CONFIGURED=true
fi

CONFIGURE_CREDENTIALS=true

if [ "$ALREADY_CONFIGURED" = true ]; then
    echo ""
    echo "⚠️  Traefik est déjà configuré (.env et .htpasswd existent)."
    echo ""
    echo "    Que voulez-vous faire ?"
    echo "    1) Conserver la configuration actuelle et continuer"
    echo "    2) Changer le nom d'utilisateur et le mot de passe"
    echo ""
    read -p "    Votre choix [1/2] : " CHOICE
    case "$CHOICE" in
        2)
            echo "    Reconfiguration des credentials..."
            CONFIGURE_CREDENTIALS=true
            ;;
        *)
            echo "    Configuration conservée."
            CONFIGURE_CREDENTIALS=false
            ;;
    esac
fi

# 1. Créer le fichier acme.json avec les bonnes permissions
mkdir -p "${TRAEFIK_DIR}/letsencrypt"
touch "${TRAEFIK_DIR}/letsencrypt/acme.json"
chmod 600 "${TRAEFIK_DIR}/letsencrypt/acme.json"
echo "    acme.json prêt"

if [ "$CONFIGURE_CREDENTIALS" = true ]; then
    # 2. Saisie et confirmation du mot de passe
    echo ""
    echo "==> Création du compte dashboard Traefik"
    read -p "    Nom d'utilisateur [admin]: " DASHBOARD_USER
    DASHBOARD_USER="${DASHBOARD_USER:-admin}"

    while true; do
        read -s -p "    Mot de passe : " DASHBOARD_PASSWORD
        echo ""
        read -s -p "    Confirmer le mot de passe : " DASHBOARD_PASSWORD_CONFIRM
        echo ""
        if [ "$DASHBOARD_PASSWORD" = "$DASHBOARD_PASSWORD_CONFIRM" ]; then
            break
        else
            echo "    ❌ Les mots de passe ne correspondent pas. Réessayez."
            echo ""
        fi
    done

    if ! command -v htpasswd &>/dev/null; then
        echo "    Installation de apache2-utils pour htpasswd..."
        sudo apt-get install -y apache2-utils -q
    fi

    HASHED=$(htpasswd -nbB "$DASHBOARD_USER" "$DASHBOARD_PASSWORD")
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
fi

echo ""
echo "==> Setup terminé. Pour démarrer Traefik :"
echo "    cd ${TRAEFIK_DIR} && docker compose up -d"
