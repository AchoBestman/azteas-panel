#!/bin/bash
set -euo pipefail

# ============================================================
# BOOTSTRAP.SH - Deploiement complet en une commande
#
# Usage : sudo bash bootstrap.sh
#
# Prerequis AVANT de lancer ce script :
#   1. Mailcow doit deja etre installe et fonctionnel sur ce VPS
#      (installation via son propre script officiel, separee)
#   2. Le dossier piler/ doit deja etre copie sur le VPS
#      (via ./sync.sh depuis ton PC, ou git clone)
#   3. Le fichier .env doit etre rempli avec tes vraies valeurs
#      (voir .env.example pour la liste complete)
#
# Ce script :
#   1. Installe toutes les dependances systeme
#   2. Configure ufw + ufw-docker
#   3. Lance la stack Piler (Docker)
#   4. Applique tous les correctifs connus (fix-piler-config.sh)
#   5. Configure l'email (msmtp + fail2ban)
#   6. Monte le Storage Box (CIFS)
#   7. Active les backups automatiques (restic -> Backblaze B2)
#
# Idempotent : peut etre relance sans danger si une etape echoue.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

log() {
    echo ""
    echo "================================================================"
    echo " $1"
    echo "================================================================"
}

# --- 0. Verifications prealables ---
log "0/8 - Verifications prealables"

if [ ! -f "${SCRIPT_DIR}/.env" ]; then
    echo "ERREUR : fichier .env introuvable."
    echo "Copie .env.example vers .env et remplis-le avant de relancer."
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "ERREUR : Docker n'est pas installe."
    echo "Installe Mailcow d'abord (qui installe Docker), ou installe Docker manuellement :"
    echo "  curl -fsSL https://get.docker.com | sh"
    exit 1
fi

if ! sudo docker network ls | grep -q mailcow-network; then
    echo "AVERTISSEMENT : aucun reseau Docker Mailcow detecte."
    echo "Verifie que Mailcow est bien installe et demarre avant de continuer."
    read -p "Continuer quand meme ? (o/N) " confirm
    [ "$confirm" = "o" ] || exit 1
fi

source .env
echo "Configuration chargee : ARCHIVE_HOST=${ARCHIVE_HOST}"

# --- 1. Dependances systeme ---
log "1/8 - Installation des dependances systeme"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y \
    curl git ufw fail2ban unattended-upgrades restic \
    cifs-utils winbind \
    msmtp msmtp-mta mailutils \
    gettext-base rsync

dpkg-reconfigure --priority=low unattended-upgrades || true

# --- 2. Pare-feu : ufw ---
log "2/8 - Configuration ufw"
ufw default deny incoming
ufw default allow outgoing

ufw allow "${SSH_PORT:-1995}/tcp" comment 'SSH'
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow "${PILER_SMTP_PORT:-2526}/tcp" comment 'Piler SMTP archiving'

yes | ufw enable || true
ufw status verbose

# --- 3. ufw-docker (empeche Docker de contourner ufw) ---
log "3/8 - Installation de ufw-docker"
if [ ! -f /usr/local/bin/ufw-docker ]; then
    wget -qO /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
    chmod +x /usr/local/bin/ufw-docker
    ufw-docker install
    systemctl restart ufw
else
    echo "ufw-docker deja installe, etape ignoree."
fi

ufw-docker allow piler 25 || true

# --- 4. Lancement de la stack Piler ---
log "4/8 - Lancement de Piler (Docker)"
mkdir -p backup
docker compose up -d
echo "Attente du demarrage complet (30s)..."
sleep 30
docker compose ps

# --- 5. Correctifs connus de l'image sutoj/piler ---
log "5/8 - Application des correctifs Piler"
bash fix-piler-config.sh

# --- 6. Email (msmtp + fail2ban) ---
log "6/8 - Configuration email et fail2ban"
bash mail/setup-mail.sh

# --- 7. Storage Box (CIFS) ---
log "7/8 - Montage du Storage Box"
if [ -f storagebox/setup-storagebox.sh ]; then
    bash storagebox/setup-storagebox.sh
else
    echo "Pas de script storagebox trouve, etape ignoree."
fi

# --- 8. Backups automatiques (restic -> Backblaze B2) ---
log "8/8 - Activation des backups automatiques"
set -a
source .env
set +a
if ! restic snapshots > /dev/null 2>&1; then
    echo "Initialisation du repository restic..."
    restic init
fi
chmod +x backup/backup-piler.sh backup/notify-failure.sh

cp backup/piler-backup.service backup/piler-backup.timer backup/status-email-backup@.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now piler-backup.timer

log "TERMINE"
echo "Verifie maintenant :"
echo "  docker compose ps"
echo "  curl -Ik https://${ARCHIVE_HOST}"
echo "  fail2ban-client status"
echo "  systemctl list-timers piler-backup.timer"
echo ""
echo "⚠️ Etapes MANUELLES restantes (non automatisees, par securite) :"
echo "  1. Durcissement SSH (port, cle uniquement) - voir GUIDE_INSTALLATION_PILER.md ETAPE 1"
echo "  2. Integration Mailcow (ADDITIONAL_SAN + vhost nginx) - voir ETAPE 7 du guide"
echo "  3. Changer le mot de passe admin Piler + activer le 2FA"
echo "  4. Configurer les BCC Maps dans Mailcow pour chaque domaine"