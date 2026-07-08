-- Idempotent : crée le role/database apanel sur le PostgreSQL partagé
-- s'ils n'existent pas encore, et resynchronise le mot de passe à chaque
-- exécution (permet de faire tourner APANEL_DB_PASSWORD simplement en
-- redéployant).
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'apanel') THEN
      CREATE ROLE apanel LOGIN;
   END IF;
END
$$;

ALTER ROLE apanel WITH LOGIN PASSWORD :'apanel_password';

SELECT 'CREATE DATABASE apanel OWNER apanel'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'apanel')\gexec

GRANT ALL PRIVILEGES ON DATABASE apanel TO apanel;
