#!/bin/bash
set -euo pipefail

# ============================================================
# Configuration UFW + ufw-docker pour Mailcow
# CE SCRIPT S'EXECUTE SUR LE VPS : ssh mailcow
# cd /opt/azteas-panel/mailcow && bash setup-ufw.sh
#
# Ports mail publiés directement par Mailcow (pas via Traefik)
# HTTP/HTTPS sont gérés par Traefik — ne pas les ajouter ici
# ============================================================

echo "==> Configuration UFW pour Mailcow"

# ----------------------------------------------------------
# 1. Règles UFW standard (INPUT chain)
# ----------------------------------------------------------
echo "    Ajout des règles UFW..."

sudo ufw allow 25/tcp    comment "SMTP entrant"
sudo ufw allow 465/tcp   comment "SMTPS"
sudo ufw allow 587/tcp   comment "SMTP submission"
sudo ufw allow 993/tcp   comment "IMAPS"
sudo ufw allow 4190/tcp  comment "ManageSieve"
sudo ufw allow 873/tcp   comment "Rsync"

echo "    Règles UFW ajoutées"

# ----------------------------------------------------------
# 2. Règles ufw-docker (DOCKER-USER chain)
# Permet au trafic externe d'atteindre les conteneurs Mailcow
# ----------------------------------------------------------
echo ""
echo "==> Configuration ufw-docker pour Mailcow"
echo "    (à exécuter après démarrage de Mailcow)"

# Postfix : SMTP
sudo ufw-docker allow mailcowdockerized-postfix-mailcow-1 25/tcp
sudo ufw-docker allow mailcowdockerized-postfix-mailcow-1 465/tcp
sudo ufw-docker allow mailcowdockerized-postfix-mailcow-1 587/tcp

# Dovecot : IMAP + ManageSieve
sudo ufw-docker allow mailcowdockerized-dovecot-mailcow-1 993/tcp
sudo ufw-docker allow mailcowdockerized-dovecot-mailcow-1 4190/tcp

echo "    Règles ufw-docker ajoutées"

echo ""
echo "==> Vérification"
sudo ufw status | grep -E "25|465|587|993|4190|873"
