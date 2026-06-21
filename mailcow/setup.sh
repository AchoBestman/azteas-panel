#!/bin/bash
set -euo pipefail

# ============================================================
# Setup Mailcow sur le VPS
# CE SCRIPT S'EXECUTE SUR LE VPS : ssh mailcow
# cd /opt/azteas-panel/mailcow && bash setup.sh
#
# Idempotent : peut être relancé sans risque.
# Ref: https://docs.mailcow.email/post_installation/reverse-proxy/r_p-traefik3/
#
# SECURITE : ce script ne logue jamais les valeurs des secrets.
# ============================================================

MAILCOW_DIR="/opt/mailcow-dockerized"
AZTEAS_MAILCOW_DIR="/opt/azteas-panel/mailcow"

echo "==> Setup Mailcow"

# Vérifier si déjà installé
if [ -d "$MAILCOW_DIR" ]; then
    echo ""
    echo "⚠️  Mailcow est déjà installé dans $MAILCOW_DIR"
    echo ""
    echo "    Que voulez-vous faire ?"
    echo "    1) Conserver l'installation actuelle et appliquer la config Traefik"
    echo "    2) Supprimer et réinstaller complètement"
    echo ""
    read -p "    Votre choix [1/2] : " CHOICE
    case "$CHOICE" in
        2)
            echo "    Suppression de l'installation existante..."
            cd "$MAILCOW_DIR" && docker compose down --volumes 2>/dev/null || true
            sudo rm -rf "$MAILCOW_DIR"
            ;;
        *)
            echo "    Conservation de l'installation existante."
            ;;
    esac
fi

# Cloner Mailcow si nécessaire
if [ ! -d "$MAILCOW_DIR" ]; then
    echo ""
    echo "==> Clonage de Mailcow..."
    sudo git clone https://github.com/mailcow/mailcow-dockerized.git "$MAILCOW_DIR"
    sudo chown -R "$USER:$USER" "$MAILCOW_DIR"
    echo "    Clonage terminé"
fi

cd "$MAILCOW_DIR"

# Générer la configuration si elle n'existe pas
# generate_config.sh génère automatiquement DBPASS, DBROOT, REDISPASS
if [ ! -f "$MAILCOW_DIR/mailcow.conf" ]; then
    echo ""
    echo "==> Génération de la configuration Mailcow..."
    MAILCOW_HOSTNAME=mail.azteas.com MAILCOW_TZ=Europe/Paris bash generate_config.sh
    echo "    Configuration générée (DBPASS, DBROOT, REDISPASS auto-générés)"
fi

# Appliquer la configuration Traefik
echo ""
echo "==> Application de la configuration Traefik..."

sed -i 's/^SKIP_LETS_ENCRYPT=.*/SKIP_LETS_ENCRYPT=y/' mailcow.conf
sed -i 's/^SKIP_HTTP_VERIFICATION=.*/SKIP_HTTP_VERIFICATION=y/' mailcow.conf

if grep -q "^AUTODISCOVER_SAN=" mailcow.conf; then
    sed -i 's/^AUTODISCOVER_SAN=.*/AUTODISCOVER_SAN=n/' mailcow.conf
else
    echo "AUTODISCOVER_SAN=n" >> mailcow.conf
fi

if grep -q "^ENABLE_IPV6=" mailcow.conf; then
    sed -i 's/^ENABLE_IPV6=.*/ENABLE_IPV6=false/' mailcow.conf
else
    echo "ENABLE_IPV6=false" >> mailcow.conf
fi

echo "    Let's Encrypt interne : désactivé"
echo "    AUTODISCOVER_SAN      : désactivé"
echo "    IPv6                  : désactivé"

cp "$AZTEAS_MAILCOW_DIR/docker-compose.override.yml" "$MAILCOW_DIR/docker-compose.override.yml"
echo "    docker-compose.override.yml appliqué"

# Installer restic si absent
if ! command -v restic &>/dev/null; then
    echo ""
    echo "==> Installation de restic..."
    sudo apt-get install -y restic -q
    echo "    restic installé"
fi

# Vérifier le .env
ENV_FILE="/opt/azteas-panel/mailcow/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo ""
    echo "⚠️  Fichier /opt/azteas-panel/mailcow/.env introuvable."
    echo "    Lancer le workflow GitHub Actions ou copier .env.example en .env."
    exit 1
fi

# Charger les variables sans les afficher
set -a; source "$ENV_FILE" > /dev/null 2>&1; set +a

# Initialiser le repo restic si nécessaire
export RESTIC_REPOSITORY
export RESTIC_PASSWORD

echo ""
echo "==> Initialisation du repository restic Backblaze B2..."
if ! restic snapshots > /dev/null 2>&1; then
    restic init > /dev/null
    echo "    Repository initialisé"
else
    echo "    Repository déjà initialisé"
fi

# Installer les units systemd
echo ""
echo "==> Installation des units systemd de backup..."
BACKUP_DIR="/opt/azteas-panel/mailcow/backup"
chmod +x "$BACKUP_DIR/backup-mailcow.sh" "$BACKUP_DIR/restore-from-b2.sh" "$BACKUP_DIR/notify-failure.sh"

sudo cp "$BACKUP_DIR/mailcow-backup.service" /etc/systemd/system/
sudo cp "$BACKUP_DIR/mailcow-backup.timer" /etc/systemd/system/

if [ ! -f /etc/systemd/system/status-email-backup@.service ]; then
    sudo tee /etc/systemd/system/status-email-backup@.service > /dev/null << 'EOF'
[Unit]
Description=Notification email d'échec pour %i

[Service]
Type=oneshot
ExecStart=/opt/azteas-panel/mailcow/backup/notify-failure.sh "%i"
EOF
fi

sudo systemctl daemon-reload
sudo systemctl enable mailcow-backup.timer
sudo systemctl start mailcow-backup.timer
echo "    Timer systemd activé : backup quotidien à 4h00"

echo ""
echo "==> Setup terminé."
echo ""
echo "    DNS requis avant de démarrer :"
VPS_IP=$(curl -s ifconfig.me)
echo "      mail.azteas.com             A      $VPS_IP"
echo "      azteas.com                  MX     mail.azteas.com"
echo "      autoconfig.azteas.com       CNAME  mail.azteas.com"
echo "      autodiscover.azteas.com     CNAME  mail.azteas.com"
echo ""
echo "    Pour démarrer Mailcow :"
echo "      cd $MAILCOW_DIR && docker compose up -d"
echo ""
echo "    Pour configurer le pare-feu :"
echo "      cd /opt/azteas-panel/mailcow && bash setup-ufw.sh"
echo ""
echo "    Pour restaurer depuis Backblaze B2 :"
echo "      cd /opt/azteas-panel/mailcow/backup && bash restore-from-b2.sh"
