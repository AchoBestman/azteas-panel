-- Idempotent : crée le role/database OpenArchiver sur le PostgreSQL partagé
-- s'ils n'existent pas encore, et resynchronise le mot de passe à chaque
-- exécution (permet de faire tourner OPENARCHIVER_DB_PASSWORD simplement en
-- redéployant).
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'openarchiver') THEN
      CREATE ROLE openarchiver LOGIN;
   END IF;
END
$$;

ALTER ROLE openarchiver WITH LOGIN PASSWORD :'openarchiver_password';

SELECT 'CREATE DATABASE openarchiver OWNER openarchiver'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'openarchiver')\gexec

GRANT ALL PRIVILEGES ON DATABASE openarchiver TO openarchiver;
