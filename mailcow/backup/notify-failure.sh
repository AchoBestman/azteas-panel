#!/bin/bash
set -uo pipefail

# ============================================================
# Envoie un email d'alerte quand le service de backup échoue
# Appelé automatiquement par status-email-backup@.service
# ============================================================

FAILED_UNIT="$1"

source /opt/azteas-panel/mailcow/.env > /dev/null 2>&1

SUBJECT="[ALERTE] Echec du service ${FAILED_UNIT} sur $(hostname)"
LOGS=$(journalctl -u "${FAILED_UNIT}" -n 50 --no-pager)

{
    echo "Le service ${FAILED_UNIT} a échoué sur $(hostname) le $(date)."
    echo ""
    echo "----- 50 dernières lignes de log -----"
    echo "${LOGS}"
} | mail -s "${SUBJECT}" "${ADMIN_EMAIL}"
