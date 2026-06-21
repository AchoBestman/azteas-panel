#!/bin/bash
set -uo pipefail

# ============================================================
# Envoie un email d'alerte quand le service de backup echoue
# Appele automatiquement par status-email-backup@.service
# ============================================================

FAILED_UNIT="$1"

source /opt/azteas-panel/piler/.env

SUBJECT="[ALERTE] Echec du service ${FAILED_UNIT} sur $(hostname)"
LOGS=$(journalctl -u "${FAILED_UNIT}" -n 50 --no-pager)

{
    echo "Le service ${FAILED_UNIT} a echoue sur $(hostname) le $(date)."
    echo ""
    echo "----- 50 dernieres lignes de log -----"
    echo "${LOGS}"
} | mail -s "${SUBJECT}" "${ADMIN_EMAIL}"
