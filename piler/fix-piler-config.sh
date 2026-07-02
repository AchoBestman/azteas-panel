#!/bin/bash
set -euo pipefail

# ============================================================
# Corrige des bugs connus de generation de config dans l'image
# sutoj/piler. A executer APRES le premier "docker compose up -d"
# (ou apres tout "docker compose down -v" qui recree le volume
# piler_etc). Idempotent : sans danger de le relancer.
# ============================================================

cd "$(dirname "${BASH_SOURCE[0]}")"

source .env

# Architecture finale : Mailcow gere le HTTPS public (port 443 standard),
# Piler n'est jamais accede directement avec un port custom.
CORRECT_SITE_URL="https://${ARCHIVE_HOST}/"

echo "=== 1/7 : Correction du port Manticore read-only ==="
docker compose exec piler sed -i \
    "s/SPHINX_HOSTNAME_READONLY'\] = 'manticore:9307'/SPHINX_HOSTNAME_READONLY'] = 'manticore:9306'/" \
    /etc/piler/config-site.php
docker compose exec piler grep SPHINX_HOSTNAME_READONLY /etc/piler/config-site.php

echo ""
echo "=== 2/7 : Correction de SITE_URL (port + https manquants) ==="
docker compose exec -T -e NEW_SITE_URL="${CORRECT_SITE_URL}" piler php < fix-site-url.php
docker compose exec piler grep "SITE_URL" /etc/piler/config-site.php

echo ""
echo "=== 3/7 : Creation des tables RT manquantes dans Manticore ==="
# L'image sutoj/piler genere la config referencant piler1/tag1/note1
# mais ne cree jamais ces tables dans Manticore au demarrage.
# On les cree nous-memes ici, idempotent grace a IF NOT EXISTS.

docker compose exec manticore mysql -h127.0.0.1 -P9306 -e \
"CREATE TABLE IF NOT EXISTS piler1 (sender text indexed, rcpt text indexed, senderdomain text indexed, rcptdomain text indexed, subject text indexed, body text indexed, attachment_types text indexed, arrived bigint, sent bigint, size uint, direction uint, folder uint, attachments uint);"

docker compose exec manticore mysql -h127.0.0.1 -P9306 -e \
"CREATE TABLE IF NOT EXISTS tag1 (tag text indexed stored, mid bigint, uid uint);"

docker compose exec manticore mysql -h127.0.0.1 -P9306 -e \
"CREATE TABLE IF NOT EXISTS note1 (note text indexed stored, mid bigint, uid uint);"

echo "Tables Manticore actuelles :"
docker compose exec manticore mysql -h127.0.0.1 -P9306 -e "SHOW TABLES;"

echo ""
echo "=== 4/7 : Correction du fuseau horaire (bug de calcul de date Accounting) ==="
# Le defaut 'Europe/Budapest' (UTC+2) combine a un arrondi naif (% 86400) dans
# model/accounting/accounting.php decale tous les calculs de date d'un jour.
# UTC elimine le probleme quelle que soit la position geographique reelle.
docker compose exec piler grep -q "'TIMEZONE'" /etc/piler/config-site.php || \
    printf "%s\n" "\$config['TIMEZONE'] = 'UTC';" | docker compose exec -T piler tee -a /etc/piler/config-site.php > /dev/null
docker compose exec piler grep TIMEZONE /etc/piler/config-site.php

echo ""
echo "=== 5/7 : Remplacement du favicon Piler par celui d'Azteas ==="
# BRANDING_FAVICON (config.php.in) est le HTML injecte dans <head> pour le
# favicon ; le fichier qu'il reference est deploye par
# customizations/www/assets/ico/azteas-favicon.ico (voir apply-customizations.sh).
docker compose exec piler grep -q "'BRANDING_FAVICON'" /etc/piler/config-site.php || \
    printf "%s\n" "\$config['BRANDING_FAVICON'] = '<link rel=\"shortcut icon\" href=\"/assets/ico/azteas-favicon.ico\" type=\"image/x-icon\">';" | docker compose exec -T piler tee -a /etc/piler/config-site.php > /dev/null
docker compose exec piler grep BRANDING_FAVICON /etc/piler/config-site.php

echo ""
echo "=== 6/7 : Feuille de style Azteas (layout liste/contenu de search.php) ==="
# CUSTOM_CSS (config.php.in) vaut '' par defaut, mais config.php.in precise
# que c'est le champ prevu pour etre expose dans l'assistant/panneau
# d'administration de Piler : config-site.php peut donc deja contenir une
# ligne "$config['CUSTOM_CSS'] = '';" (generee par Piler lui-meme) AVANT
# notre premier passage, ce qui ferait echouer silencieusement un simple
# "grep -q ... || append" (la ligne "existe" deja, vide). On remplace donc la
# ligne si elle existe, sinon on l'ajoute. Le fichier reference est deploye
# par customizations/www/assets/css/azteas-panes.css (voir apply-customizations.sh).
# Cache-buster automatique : sans parametre de version, le navigateur peut
# garder azteas-panes.css en cache indefiniment (aucune invalidation cote
# client sinon), donc un changement de CSS deploye avec succes peut rester
# invisible pour un visiteur qui l'a deja charge une fois. Le hash est calcule
# sur le fichier local (deja synchronise sur le VPS par rsync avant ce
# script), donc il change automatiquement des que le contenu change.
CSS_VERSION=$(md5sum "$(dirname "${BASH_SOURCE[0]}")/customizations/www/assets/css/azteas-panes.css" | cut -c1-8)
if docker compose exec piler grep -q "config\['CUSTOM_CSS'\]" /etc/piler/config-site.php; then
    docker compose exec piler sed -i "s#\\\$config\['CUSTOM_CSS'\].*#\$config['CUSTOM_CSS'] = '<link rel=\"stylesheet\" href=\"/assets/css/azteas-panes.css?v=${CSS_VERSION}\">';#" /etc/piler/config-site.php
else
    printf "%s\n" "\$config['CUSTOM_CSS'] = '<link rel=\"stylesheet\" href=\"/assets/css/azteas-panes.css?v=${CSS_VERSION}\">';" | docker compose exec -T piler tee -a /etc/piler/config-site.php > /dev/null
fi
docker compose exec piler grep CUSTOM_CSS /etc/piler/config-site.php

echo ""
echo "=== Ajout du domaine ${ARCHIVE_HOST#archive.} dans le registre interne Piler ==="
# Piler a son propre registre de domaines (separe de Mailcow) utilise pour
# filtrer les stats d'Accounting (get_mapped_domains()). Sans cette entree,
# generate_stats.php ignore silencieusement tous les emails du domaine.
MAIN_DOMAIN="${MAIL_DOMAIN:-${ARCHIVE_HOST#archive.}}"
docker compose exec mysql mariadb -u piler -p"${MYSQL_PASSWORD}" piler -e \
    "INSERT IGNORE INTO domain (domain, mapped, ldap_id) VALUES ('${MAIN_DOMAIN}', '${MAIN_DOMAIN}', 0);"
docker compose exec mysql mariadb -u piler -p"${MYSQL_PASSWORD}" piler -e "SELECT * FROM domain;"

echo ""
echo "=== 7/7 : Application des personnalisations d'interface (si presentes) ==="
if [ -f "$(dirname "${BASH_SOURCE[0]}")/customizations/apply-customizations.sh" ]; then
    bash "$(dirname "${BASH_SOURCE[0]}")/customizations/apply-customizations.sh" || true
fi

echo ""
echo "Redemarrage de Piler pour appliquer les corrections..."
docker compose restart piler

echo ""
echo "Termine. Patiente quelques secondes puis verifie :"
echo "  docker compose ps piler"
echo "  curl -Ik ${CORRECT_SITE_URL}"
