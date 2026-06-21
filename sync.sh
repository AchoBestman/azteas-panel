#!/bin/bash
set -euo pipefail

# ============================================================
# Synchronise azteas-panel vers le VPS via rsync
# Utilise l'alias SSH défini dans ~/.ssh/config : "mailcow"
#
# Usage :
#   ./sync.sh                  → sync tout azteas-panel
#   ./sync.sh traefik          → sync uniquement le service traefik
#   ./sync.sh piler            → sync uniquement le service piler
#
# Prérequis : alias "mailcow" défini dans ~/.ssh/config
# ============================================================

SSH_ALIAS="mailcow"
REMOTE_BASE="/opt/azteas-panel"
SERVICE="${1:-}"

if [ -n "$SERVICE" ]; then
    if [ ! -d "$SERVICE" ]; then
        echo "Erreur : le dossier '$SERVICE' n'existe pas localement."
        exit 1
    fi
    LOCAL_PATH="./$SERVICE/"
    REMOTE_PATH="${REMOTE_BASE}/${SERVICE}/"
    echo "Synchronisation du service : $SERVICE"
else
    LOCAL_PATH="./"
    REMOTE_PATH="${REMOTE_BASE}/"
    echo "Synchronisation complète de azteas-panel"
fi

rsync -avz --delete --itemize-changes \
    --exclude '.git' \
    --exclude '.DS_Store' \
    --exclude '.env' \
    --exclude '*.log' \
    --exclude 'data/' \
    --exclude 'volumes/' \
    "$LOCAL_PATH" "${SSH_ALIAS}:${REMOTE_PATH}"

echo ""
echo "Synchronisation terminée vers ${SSH_ALIAS}:${REMOTE_PATH}"

if [ -n "$SERVICE" ]; then
    echo ""
    echo "Pour appliquer sur le VPS :"
    echo "  ssh ${SSH_ALIAS} 'cd ${REMOTE_BASE}/${SERVICE} && docker compose up -d'"
fi
