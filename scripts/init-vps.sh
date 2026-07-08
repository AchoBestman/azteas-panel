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
# 2. Créer le dossier de logs Traefik (pour fail2ban)
# ----------------------------------------------------------
sudo mkdir -p /var/log/traefik
sudo chmod 755 /var/log/traefik

# ----------------------------------------------------------
# 3. Ajouter l'utilisateur au groupe docker
# ----------------------------------------------------------
sudo usermod -aG docker $USER
newgrp docker

# ----------------------------------------------------------
# 4. Autoriser Traefik à recevoir le trafic web via ufw-docker
# IMPORTANT : à relancer à chaque nouveau service exposé publiquement
# ----------------------------------------------------------
sudo ufw-docker allow traefik 80
sudo ufw-docker allow traefik 443
# Passthrough TCP PostgreSQL/Redis (accès externe, ex: apanel/Vercel)
sudo ufw-docker allow traefik 5432
sudo ufw-docker allow traefik 6380

# ----------------------------------------------------------
# 5. Autoriser sudo sans mot de passe pour Coolify (déploiements)
# ----------------------------------------------------------
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/coolify
sudo chmod 440 /etc/sudoers.d/coolify

# ----------------------------------------------------------
# 6. Tuer les processus orphelins à la déconnexion SSH
#    Evite que des processus lancés en SSH restent actifs après déconnexion
#    Les conteneurs Docker ne sont pas affectés (tournent sous dockerd)
# ----------------------------------------------------------
sudo sed -i 's/^#KillUserProcesses=no/KillUserProcesses=yes/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# Limiter le nombre de processus par utilisateur
echo "$USER soft nproc 4096" | sudo tee -a /etc/security/limits.conf
echo "$USER hard nproc 8192" | sudo tee -a /etc/security/limits.conf

# ----------------------------------------------------------
# 7. Vérification
# ----------------------------------------------------------
ls -la /opt/
docker ps
sudo ufw status
COMMANDS

echo ""
echo "Ensuite depuis ta machine locale :"
echo "  ./sync.sh"
