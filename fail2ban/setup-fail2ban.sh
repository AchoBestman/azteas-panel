#!/bin/bash
set -euo pipefail

# ============================================================
# Setup fail2ban global pour azteas-panel
# CE SCRIPT S'EXECUTE SUR LE VPS
# cd /opt/azteas-panel/fail2ban && bash setup-fail2ban.sh
#
# Protège via le log Traefik : Piler, Mailcow, dashboard Traefik
# Protège également SSH directement
# ============================================================

FAIL2BAN_DIR="/opt/azteas-panel/fail2ban"
ENV_FILE="/opt/azteas-panel/.env"

echo "==> Setup fail2ban"

# Installer fail2ban si absent
if ! command -v fail2ban-client &>/dev/null; then
    echo "    Installation de fail2ban..."
    sudo apt-get install -y fail2ban -q
    echo "    fail2ban installé"
fi

# Charger le .env global pour SSH_PORT, ADMIN_EMAIL, SMTP_FROM
if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️  /opt/azteas-panel/.env introuvable — créer ce fichier avec SSH_PORT, ADMIN_EMAIL, SMTP_FROM"
    exit 1
fi
source "$ENV_FILE" > /dev/null 2>&1

# Copier les filtres
echo "    Copie des filtres..."
sudo cp "$FAIL2BAN_DIR/filter.d/"*.conf /etc/fail2ban/filter.d/

# Générer le jail depuis le template
echo "    Génération du jail..."
sed \
    -e "s|\${ADMIN_EMAIL}|${ADMIN_EMAIL}|g" \
    -e "s|\${SMTP_FROM}|${SMTP_FROM:-noreply@azteas.com}|g" \
    -e "s|\${SSH_PORT}|${SSH_PORT:-1995}|g" \
    "$FAIL2BAN_DIR/jail.d/azteas.local.template" \
    | sudo tee /etc/fail2ban/jail.d/azteas.local > /dev/null

# Redémarrer fail2ban
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban

echo ""
echo "==> Vérification"
sudo fail2ban-client status
