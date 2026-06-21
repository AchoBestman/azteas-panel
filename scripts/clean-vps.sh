#!/bin/bash
# ============================================================
# NETTOYAGE COMPLET DU VPS
# ============================================================
# CE SCRIPT NE S'EXECUTE PAS LOCALEMENT.
# Il documente les commandes SSH à exécuter manuellement
# sur le VPS pour repartir d'une base propre.
#
# CONSERVE : configuration sécurité (ufw, fail2ban, sshd, user)
# SUPPRIME  : toutes les applications Docker et leurs données
#
# Prérequis : être connecté en SSH sur le VPS
#   ssh mailcow
# ============================================================

echo "Ce script est une documentation des commandes à exécuter sur le VPS."
echo "Connecte-toi d'abord : ssh mailcow"
echo ""
echo "Commandes à exécuter dans l'ordre :"
echo ""
cat << 'COMMANDS'
# ----------------------------------------------------------
# 1. Arrêter tous les conteneurs en cours
# ----------------------------------------------------------
docker ps -q | xargs -r docker stop

# ----------------------------------------------------------
# 2. Supprimer tous les conteneurs
# ----------------------------------------------------------
docker ps -aq | xargs -r docker rm -f

# ----------------------------------------------------------
# 3. Supprimer toutes les images Docker
# ----------------------------------------------------------
docker images -q | xargs -r docker rmi -f

# ----------------------------------------------------------
# 4. Supprimer tous les volumes Docker
# ----------------------------------------------------------
docker volume ls -q | xargs -r docker volume rm

# ----------------------------------------------------------
# 5. Supprimer tous les réseaux Docker personnalisés
# ----------------------------------------------------------
docker network ls --filter type=custom -q | xargs -r docker network rm

# ----------------------------------------------------------
# 6. Nettoyage complet Docker (cache, build, etc.)
# ----------------------------------------------------------
docker system prune -af --volumes

# ----------------------------------------------------------
# 7. Supprimer les dossiers applicatifs
# ----------------------------------------------------------
sudo rm -rf /opt/mailcow-dockerized
sudo rm -rf /opt/piler
sudo rm -rf /opt/azteas-panel

# ----------------------------------------------------------
# 8. Démonter le Hetzner Storage Box si monté
# ----------------------------------------------------------
sudo umount /mnt/storagebox || true
sudo rm -rf /mnt/storagebox

# ----------------------------------------------------------
# 9. Supprimer les entrées fstab liées aux montages CIFS
#    Editer manuellement /etc/fstab et retirer la ligne storagebox
# ----------------------------------------------------------
sudo nano /etc/fstab

# ----------------------------------------------------------
# 10. Supprimer les credentials CIFS
# ----------------------------------------------------------
sudo rm -f /etc/cifs-credentials

# ----------------------------------------------------------
# 11. Vérification finale : tout doit être vide
# ----------------------------------------------------------
docker ps -a
docker images
docker volume ls
docker network ls
ls /opt/

# ----------------------------------------------------------
# CE QUI EST CONSERVÉ (ne pas toucher)
# ----------------------------------------------------------
# - Configuration UFW        : sudo ufw status
# - Configuration fail2ban   : /etc/fail2ban/
# - Configuration SSH        : /etc/ssh/sshd_config
# - Utilisateur système      : ton user non-root avec sudo
# - Clés SSH autorisées      : ~/.ssh/authorized_keys
COMMANDS
