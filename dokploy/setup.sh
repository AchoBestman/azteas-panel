#!/bin/bash
set -euo pipefail

# ============================================================
# Setup Dokploy sur le VPS
# CE SCRIPT S'EXECUTE SUR LE VPS
# cd /opt/azteas-panel/dokploy && bash setup.sh
# ============================================================

echo "==> Setup Dokploy"

# S'assurer que le réseau azteas-net existe
if ! docker network inspect azteas-net >/dev/null 2>&1; then
    echo "    Création du réseau azteas-net..."
    docker network create azteas-net
fi
echo "    Réseau azteas-net OK"

echo ""
echo "==> Setup terminé. Pour démarrer Dokploy :"
echo "    cd /opt/azteas-panel/dokploy && docker compose up -d"
echo ""
echo "    Accès : https://dokploy.azteas.com"
