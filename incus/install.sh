#!/bin/bash
set -euo pipefail

# ============================================================
# Installation Incus sur le VPS (idempotent)
# CE SCRIPT S'EXECUTE SUR LE VPS
# cd /opt/azteas-panel/incus && bash install.sh
#
# Incus gère des ponts réseau, pools de stockage et cgroups
# directement sur l'hôte — contrairement aux autres services de ce
# repo ce n'est PAS un conteneur Docker (voir README.md).
# ============================================================

INCUS_DIR="/opt/azteas-panel/incus"
ENV_FILE="$INCUS_DIR/.env"

echo "==> Setup Incus"

if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️  $ENV_FILE introuvable — lancer le workflow GitHub Actions d'abord."
    exit 1
fi
set -a; source "$ENV_FILE" > /dev/null 2>&1; set +a
INCUS_STORAGE_SIZE="${INCUS_STORAGE_SIZE:-100GiB}"

# ---- Installation du paquet (dépôt Zabbly, source officielle Incus) ----
if ! command -v incus &>/dev/null; then
    echo "    Installation d'Incus (dépôt Zabbly)..."
    sudo mkdir -p /etc/apt/keyrings
    sudo curl -fsSL -o /etc/apt/keyrings/zabbly.asc https://pkgs.zabbly.com/key.asc
    . /etc/os-release
    echo "deb [signed-by=/etc/apt/keyrings/zabbly.asc] https://pkgs.zabbly.com/incus/stable ${VERSION_CODENAME} main" \
        | sudo tee /etc/apt/sources.list.d/zabbly-incus-stable.list > /dev/null
    sudo apt-get update -q
    sudo apt-get install -y incus incus-ui-canonical zfsutils-linux -q
    echo "    Incus installé"
else
    echo "    Incus déjà installé"
fi

# ---- ZFS requis pour les quotas de stockage par environnement client ----
if ! sudo modprobe zfs 2>/dev/null; then
    echo "❌ Le module ZFS ne charge pas sur ce noyau — les quotas de stockage"
    echo "   par client (l'objectif principal d'Incus ici) ne fonctionneront"
    echo "   pas avec un pool ZFS. Vérifier manuellement sur le VPS avant de"
    echo "   continuer (zfs-dkms, headers noyau) plutôt que de basculer sur"
    echo "   un driver de stockage sans quota."
    exit 1
fi

# ---- Utilisateur SSH dans le groupe incus-admin (comme docker, cf. scripts/init-vps.sh) ----
if ! groups "$USER" | grep -q incus-admin; then
    sudo usermod -aG incus-admin "$USER"
    echo "    $USER ajouté au groupe incus-admin (reconnexion SSH nécessaire pour un usage sans sudo)"
fi

# ---- Initialisation — une seule fois. Ne JAMAIS relancer sur un pool
#      existant (écraserait l'environnement d'éventuels clients déjà
#      provisionnés) : on vérifie qu'aucun pool n'existe avant d'initialiser.
#      La taille du pool, elle, est réappliquée à chaque déploiement
#      juste en dessous (bloc suivant) — seule l'init elle-même est figée.
if sudo incus storage list -f csv 2>/dev/null | grep -q .; then
    echo "    Incus déjà initialisé (pool de stockage existant) — init ignorée"
else
    echo "    Initialisation d'Incus (pool ZFS ${INCUS_STORAGE_SIZE}, réseau incusbr0)..."
    sed "s|\${INCUS_STORAGE_SIZE}|${INCUS_STORAGE_SIZE}|g" \
        "$INCUS_DIR/preseed.yml.template" | sudo incus admin init --preseed
    echo "    Incus initialisé"
fi

# ---- Appliquer INCUS_STORAGE_SIZE à chaque déploiement (pas seulement au
#      premier). Un pool ZFS loop ne peut que grandir, jamais rétrécir —
#      si la valeur demandée est inférieure ou égale à la taille actuelle,
#      Incus/ZFS refuse le changement : on capture l'échec pour ne pas faire
#      échouer tout le déploiement, et on avertit plutôt que de tenter
#      quoi que ce soit de destructif (réduire un pool existant demande une
#      migration manuelle vers un nouveau pool, pas automatisable ici).
echo "    Application de la taille de pool demandée (${INCUS_STORAGE_SIZE})..."
if sudo incus storage set default size="$INCUS_STORAGE_SIZE"; then
    echo "    Taille du pool : ${INCUS_STORAGE_SIZE}"
else
    echo "⚠️  INCUS_STORAGE_SIZE=${INCUS_STORAGE_SIZE} n'a pas pu être appliqué"
    echo "    (taille actuelle : $(sudo incus storage get default size)). Un pool"
    echo "    ZFS loop ne rétrécit jamais automatiquement — le pool reste à sa"
    echo "    taille actuelle, rien n'a été modifié ni supprimé."
fi

# ---- API HTTPS accessible depuis Traefik (conteneur Docker, via
#      host.docker.internal) — commande idempotente, sans risque à
#      relancer à chaque déploiement. Port 9443, pas 8443 : 8443 est déjà
#      pris par Mailcow (HTTPS_PORT) sur ce même VPS.
sudo incus config set core.https_address 0.0.0.0:9443

# ---- Autoriser SEULEMENT azteas-net (le réseau Docker de Traefik) à
#      atteindre le port 9443 de l'hôte — pas le reste d'internet. C'est
#      l'inverse du rôle de ufw-docker (déjà utilisé ailleurs, cf.
#      scripts/init-vps.sh) : ufw-docker gère l'accès externe à un port
#      PUBLIÉ par un conteneur, alors qu'ici c'est un conteneur (Traefik)
#      qui doit atteindre un processus sur l'hôte — ufw-docker ne
#      s'applique donc pas à ce sens de trafic, une règle ufw normale
#      scoped sur le sous-réseau suffit. "ufw allow" est idempotent
#      (ignore les doublons), donc sans risque à chaque déploiement.
AZTEAS_NET_SUBNET=$(sudo docker network inspect azteas-net --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)
if [ -n "$AZTEAS_NET_SUBNET" ]; then
    sudo ufw allow from "$AZTEAS_NET_SUBNET" to any port 9443 proto tcp comment "Traefik -> Incus (azteas-net)"
    echo "    ufw : ${AZTEAS_NET_SUBNET} -> 9443/tcp autorisé (idempotent)"
else
    echo "⚠️  Sous-réseau azteas-net introuvable (docker network inspect a"
    echo "    échoué) — autoriser manuellement :"
    echo "    sudo ufw allow from <subnet-azteas-net> to any port 9443 proto tcp"
fi

echo ""
echo "==> Setup terminé."
echo "    Vérifier que le port 9443 n'est PAS accessible depuis internet"
echo "    (seulement depuis azteas-net) : sudo ufw status | grep 9443"
echo ""
echo "    Première connexion à https://cpanel.azteas.com :"
echo "      sudo incus config trust add admin"
echo "      → coller le token affiché dans l'écran de pairing de l'UI"
echo ""
echo "==> Vérification"
sudo incus storage list
echo "    Taille actuelle du pool 'default' : $(sudo incus storage get default size)"
if sudo systemctl is-active --quiet incus; then
    echo "    incus : actif"
else
    echo "⚠️  incus ne démarre pas — logs :"
    sudo journalctl -u incus --no-pager -n 30
    exit 1
fi
