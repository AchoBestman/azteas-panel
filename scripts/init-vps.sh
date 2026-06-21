#!/bin/bash
# ============================================================
# INITIALISATION DU VPS - commandes SSH à exécuter une seule fois
# ============================================================
# CE SCRIPT NE S'EXECUTE PAS LOCALEMENT.
# Il documente les commandes SSH à exécuter manuellement
# pour préparer le VPS avant le premier sync.
#
# Prérequis : être connecté en SSH sur le VPS
#   ssh mailcow
# ============================================================

echo "Ce script est une documentation des commandes à exécuter sur le VPS."
echo "Connecte-toi d'abord : ssh mailcow"
echo ""
cat << 'COMMANDS'
# ----------------------------------------------------------
# 1. Créer le dossier de base avec les bonnes permissions
# ----------------------------------------------------------
sudo mkdir -p /opt/azteas-panel
sudo chown $USER:$USER /opt/azteas-panel

# ----------------------------------------------------------
# 2. Vérification
# ----------------------------------------------------------
ls -la /opt/
COMMANDS

echo ""
echo "Ensuite depuis ta machine locale, relance :"
echo "  ./sync.sh"
