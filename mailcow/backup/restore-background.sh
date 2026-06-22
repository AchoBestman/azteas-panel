#!/bin/bash

# ============================================================
# Lance la restauration Mailcow en arrière-plan via screen
# Tu peux fermer ton terminal — la restauration continue.
#
# Usage :
#   bash restore-background.sh           → restaure "latest"
#   bash restore-background.sh SNAPSHOT  → restaure un snapshot précis
#
# Suivre la progression depuis n'importe où :
#   tail -f /var/log/mailcow-restore.log
#
# Reprendre la session interactive :
#   screen -r mailcow-restore
# ============================================================

SNAPSHOT="${1:-latest}"
SESSION="mailcow-restore"
LOG_FILE="/var/log/mailcow-restore.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Installer screen si absent
if ! command -v screen &>/dev/null; then
    echo "Installation de screen..."
    sudo apt-get install -y screen -q
fi

# Vérifier qu'une restauration n'est pas déjà en cours
if screen -list | grep -q "$SESSION"; then
    echo "⚠️  Une restauration est déjà en cours."
    echo ""
    echo "Pour suivre sa progression :"
    echo "  tail -f $LOG_FILE"
    echo ""
    echo "Pour reprendre la session interactive :"
    echo "  screen -r $SESSION"
    exit 1
fi

echo "==> Lancement de la restauration Mailcow en arrière-plan..."
echo "    Snapshot  : $SNAPSHOT"
echo "    Log       : $LOG_FILE"
echo ""

# Lancer dans screen en arrière-plan
screen -dmS "$SESSION" bash "$SCRIPT_DIR/restore-from-b2.sh" "$SNAPSHOT"

echo "✅ Restauration démarrée en arrière-plan (session screen: $SESSION)"
echo ""
echo "Commandes utiles :"
echo "  Suivre le log          : tail -f $LOG_FILE"
echo "  Reprendre la session   : screen -r $SESSION"
echo "  Lister les sessions    : screen -ls"
echo "  Vérifier si terminé    : screen -ls | grep $SESSION || echo 'Terminée'"
