#!/bin/sh
set -eu

# Monte le MEME volume nommé que postgresql/ (postgresql_data, déclaré
# "external" dans docker-compose.yml) pour éditer pg_hba.conf directement —
# Postgres ne verrouille pas ce fichier en continu, il le relit seulement au
# démarrage et sur SIGHUP/pg_reload_conf(), donc l'éditer pendant que le
# conteneur tourne est sans risque.
PG_HBA=/var/lib/postgresql/data/pg_hba.conf

if [ ! -f "$PG_HBA" ]; then
  echo "pg_hba.conf introuvable à $PG_HBA — vérifier le montage du volume postgresql_data." >&2
  exit 1
fi

if grep -q '^hostssl all apanel all scram-sha-256$' "$PG_HBA"; then
  echo "pg_hba.conf déjà configuré pour apanel (TLS obligatoire), inchangé."
else
  # pg_hba.conf est évalué de haut en bas, premier match gagnant : nos règles
  # pour le role apanel doivent précéder la règle générique "host all all ..."
  # existante, sous peine de ne jamais être atteintes. On les insère juste
  # avant la première ligne commençant par "host" (awk, plus portable/lisible
  # qu'un sed d'insertion à occurrence unique).
  awk '
    !done && /^host/ {
      print "hostssl all apanel all scram-sha-256"
      print "host    all apanel all reject"
      done = 1
    }
    { print }
  ' "$PG_HBA" > "$PG_HBA.tmp"
  mv "$PG_HBA.tmp" "$PG_HBA"
  echo "pg_hba.conf mis à jour : TLS obligatoire pour le role apanel."
fi

until pg_isready -h postgresql -U "$POSTGRES_USER" > /dev/null 2>&1; do
  echo "En attente du PostgreSQL partagé..."
  sleep 2
done

PGPASSWORD="$POSTGRES_PASSWORD" psql -h postgresql -U "$POSTGRES_USER" -d postgres \
  -c "SELECT pg_reload_conf();"

echo "Configuration pg_hba.conf rechargée (pg_reload_conf)."
