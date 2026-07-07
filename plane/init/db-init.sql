-- Idempotent : crée le role/database Plane sur le PostgreSQL partagé s'ils
-- n'existent pas encore, et resynchronise le mot de passe à chaque exécution
-- (permet de faire tourner PLANE_DB_PASSWORD simplement en redéployant).
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'plane') THEN
      CREATE ROLE plane LOGIN;
   END IF;
END
$$;

ALTER ROLE plane WITH LOGIN PASSWORD :'plane_password';

SELECT 'CREATE DATABASE plane OWNER plane'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'plane')\gexec

GRANT ALL PRIVILEGES ON DATABASE plane TO plane;
