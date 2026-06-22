#!/bin/bash
set -euo pipefail

# ============================================================
# Setup Coolify sur le VPS
# CE SCRIPT S'EXECUTE SUR LE VPS
# cd /opt/azteas-panel/coolify && bash setup.sh
# ============================================================

ENV_FILE="/opt/azteas-panel/coolify/.env"

echo "==> Setup Coolify"

if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️  /opt/azteas-panel/coolify/.env introuvable."
    echo "    Lancer le workflow GitHub Actions d'abord."
    exit 1
fi

set -a; source "$ENV_FILE" > /dev/null 2>&1; set +a

# Vérifier que les variables générées existent
if [ -z "${COOLIFY_APP_ID:-}" ] || [ -z "${COOLIFY_APP_KEY:-}" ]; then
    echo "⚠️  COOLIFY_APP_ID ou COOLIFY_APP_KEY manquants — ils doivent être générés."
    echo "    Ajouter ces valeurs dans GitHub secrets/variables et relancer le workflow."
    exit 1
fi

# Créer le dossier de config système
sudo mkdir -p /etc/coolify
echo "    /etc/coolify créé"

echo ""
echo "==> Setup terminé. Pour démarrer Coolify :"
echo "    cd /opt/azteas-panel/coolify && docker compose up -d"
echo ""
echo "    Accès : https://coolify.azteas.com"
