#!/bin/bash
set -euo pipefail

# ============================================================
# APPLY-CUSTOMIZATIONS.SH
#
# Reapplique NOS modifications de l'interface Piler par-dessus
# l'image officielle, a chaque fois qu'on en a besoin (apres un
# "docker compose up -d", une mise a jour d'image, un "down -v").
#
# Principe : on ne modifie JAMAIS les fichiers de Piler directement
# dans le conteneur. On garde NOS versions dans ce dossier
# (customizations/), structuree exactement comme l'interieur du
# conteneur, et ce script les copie par-dessus a la demande.
#
# Structure attendue :
#   customizations/www/...   -> copie vers /var/piler/www/...
#   customizations/etc/...   -> copie vers /etc/piler/...
#
# Exemple concret (le jour ou tu ajoutes une personnalisation) :
#   customizations/www/assets/images/branding-logo.png
#   -> sera copie vers /var/piler/www/assets/images/branding-logo.png
#
# Usage : sudo bash customizations/apply-customizations.sh
# Idempotent : sans danger de le relancer, vide ou plein.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PILER_DIR="$(dirname "${SCRIPT_DIR}")"

cd "${PILER_DIR}"

WWW_SRC="${SCRIPT_DIR}/www"
ETC_SRC="${SCRIPT_DIR}/etc"

APPLIED=0

if [ -d "${WWW_SRC}" ] && [ -n "$(find "${WWW_SRC}" -type f 2>/dev/null)" ]; then
    echo "Application des personnalisations dans /var/piler/www/ ..."
    docker compose cp "${WWW_SRC}/." piler:/var/piler/www/
    APPLIED=1
else
    echo "Aucune personnalisation dans customizations/www/ (rien a faire)."
fi

if [ -d "${ETC_SRC}" ] && [ -n "$(find "${ETC_SRC}" -type f 2>/dev/null)" ]; then
    echo "Application des personnalisations dans /etc/piler/ ..."
    docker compose cp "${ETC_SRC}/." piler:/etc/piler/
    APPLIED=1
else
    echo "Aucune personnalisation dans customizations/etc/ (rien a faire)."
fi

if [ "${APPLIED}" -eq 1 ]; then
    echo "Redemarrage de Piler pour prendre en compte les changements..."
    docker compose restart piler
    echo "Termine."
else
    echo "Rien a appliquer pour l'instant. Place tes fichiers dans"
    echo "customizations/www/ ou customizations/etc/ (meme arborescence"
    echo "que dans le conteneur) puis relance ce script."
fi
