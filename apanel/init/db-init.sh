#!/bin/sh
set -eu

until pg_isready -h postgresql -U "$POSTGRES_USER" > /dev/null 2>&1; do
  echo "En attente du PostgreSQL partagé..."
  sleep 2
done

psql -h postgresql -U "$POSTGRES_USER" -d postgres \
  -v ON_ERROR_STOP=1 \
  -v apanel_password="$APANEL_DB_PASSWORD" \
  -f /init/db-init.sql

echo "PostgreSQL provisionné pour apanel (database=apanel, role=apanel)."
