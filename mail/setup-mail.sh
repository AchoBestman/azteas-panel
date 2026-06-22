#!/bin/bash
set -euo pipefail

# ============================================================
# Configure l'envoi d'email pour fail2ban via SMTP (msmtp)
# CE SCRIPT S'EXECUTE SUR LE VPS en root/sudo
# cd /opt/azteas-panel/mail && sudo bash setup-mail.sh
# ============================================================

SCRIPT_DIR="/opt/azteas-panel/mail"
ENV_FILE="/opt/azteas-panel/.env"

echo "[1/4] Chargement de la configuration..."
if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️  /opt/azteas-panel/.env introuvable"
    exit 1
fi
source "$ENV_FILE" > /dev/null 2>&1

echo "[2/4] Installation de msmtp et mailutils..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y msmtp msmtp-mta mailutils -q

echo "[3/4] Génération de /etc/msmtprc..."

# Port 587 = STARTTLS, port 465 = TLS implicite
if [ "${SMTP_PORT}" = "587" ]; then
    SMTP_STARTTLS="on"
else
    SMTP_STARTTLS="off"
fi

export SMTP_HOST SMTP_PORT SMTP_STARTTLS SMTP_USER SMTP_PASSWORD SMTP_FROM ADMIN_EMAIL
envsubst < "${SCRIPT_DIR}/msmtprc.template" > /etc/msmtprc
chmod 640 /etc/msmtprc
chown root:msmtp /etc/msmtprc

echo "[4/4] Configuration de msmtp comme MTA système..."
update-alternatives --install /usr/sbin/sendmail sendmail /usr/bin/msmtp 50
update-alternatives --set sendmail /usr/bin/msmtp

# Ajouter l'utilisateur courant au groupe msmtp pour lire /etc/msmtprc
REAL_USER="${SUDO_USER:-$USER}"
if [ -n "$REAL_USER" ] && ! groups "$REAL_USER" | grep -q msmtp; then
    usermod -aG msmtp "$REAL_USER"
    echo "    Utilisateur $REAL_USER ajouté au groupe msmtp (reconnexion SSH nécessaire)"
fi

echo ""
echo "==> Configuration terminée. Test d'envoi :"
echo "  echo 'Test mail VPS' | mail -s 'Test SMTP azteas-panel' ${ADMIN_EMAIL}"
