#!/bin/bash
set -euo pipefail

# ============================================================
# Configuration UFW + ufw-docker pour Piler
# CE SCRIPT S'EXECUTE SUR LE VPS après démarrage de Piler
# cd /opt/azteas-panel/piler && bash setup-ufw.sh
# ============================================================

echo "==> Configuration UFW pour Piler"

# Port SMTP archivage (BCC depuis Mailcow)
sudo ufw allow 2526/tcp comment "Piler SMTP archiving"
echo "    UFW : port 2526/tcp autorisé"

# ufw-docker pour que le trafic atteigne le conteneur piler
sudo ufw-docker allow piler 2526/tcp
echo "    ufw-docker : piler 2526/tcp autorisé"

echo ""
echo "==> Vérification"
sudo ufw status | grep 2526
