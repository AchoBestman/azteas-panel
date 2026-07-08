# Apanel — Provisioning

[apanel](https://vercel.com) (TanStack Start + Prisma + BullMQ) est
déployé sur **Vercel**, pas sur ce VPS. Ce dossier ne contient donc aucun
conteneur applicatif — seulement le provisioning des identifiants dédiés sur
les services partagés (`postgresql/`, `redis/`) que l'app consomme à distance,
via l'accès externe Traefik TCP (voir `traefik/` et `postgresql/`, `redis/`).

## Dépendances

| Service partagé | Utilisation par apanel |
|---|---|
| `postgresql/` | Base `apanel`, role `apanel` |
| `redis/` | Queue BullMQ (retries email), préfixe de clés `apanel:*` |

**Ces 2 services doivent déjà être déployés avant de lancer ce provisioning.**

## Provisioning automatique

Trois conteneurs one-shot (dossier `init/`) créent/resynchronisent les
identifiants dédiés sur les services partagés :

- `apanel-db-init` → crée la base + le role PostgreSQL `apanel`
- `apanel-redis-init` → crée le user ACL Redis `apanel`,
  restreint au préfixe de clés `apanel:*` et privé des commandes
  dangereuses (`-@dangerous` : FLUSHALL, FLUSHDB, CONFIG, KEYS, SHUTDOWN...)
- `apanel-pg-hba-init` → force le TLS pour le role `apanel` dans
  `pg_hba.conf` (voir section dédiée plus bas)

Idempotents : sans effet si tout existe déjà, sauf resynchronisation du mot
de passe. Utilisent les identifiants **admin** des services partagés
uniquement pour ce provisioning — apanel se connecte ensuite avec
ses identifiants dédiés, jamais les admin.

⚠️ **Important côté app (Vercel)** : le client Redis/BullMQ doit être
configuré avec le préfixe de clés `apanel:` (option `prefix` de BullMQ),
sinon le user ACL dédié ne pourra lire/écrire aucune clé.

## Prérequis

Générer les secrets dédiés avant le premier déploiement :

```bash
openssl rand -hex 20   # APANEL_DB_PASSWORD
openssl rand -hex 20   # APANEL_REDIS_PASSWORD
```

Secrets GitHub à définir (Settings → Secrets → Actions) :
- `APANEL_DB_PASSWORD`
- `APANEL_REDIS_PASSWORD`

Les secrets/variables des services partagés (`POSTGRES_USER`,
`POSTGRES_PASSWORD`, `REDIS_PASSWORD`) doivent déjà exister dans GitHub —
rien à ajouter pour ceux-là.

## Déploiement

```bash
./sync.sh apanel
ssh mailcow
cd /opt/azteas-panel/apanel
docker compose up
docker compose ps
```

Les conteneurs `apanel-db-init` / `-redis-init` / `-pg-hba-init` tournent
puis s'arrêtent (`restart: "no"`) — c'est normal.

## TLS obligatoire côté Postgres pour le role `apanel`

`postgresql/` active `ssl=on` mais son `pg_hba.conf` par défaut (généré par
l'image officielle) accepte aussi bien `host` (non chiffré) que TLS pour
toutes les IP. `apanel-pg-hba-init` ([init/pg-hba-init.sh](init/pg-hba-init.sh))
automatise le durcissement pour le role `apanel` :

1. Monte le **même volume** `postgresql_data` que le service `postgresql`
   (déclaré `external:` dans `docker-compose.yml`, nom réel
   `postgresql_postgresql_data` — Docker Compose préfixe les volumes du nom
   de projet, ici `postgresql` puisque déployé depuis
   `/opt/azteas-panel/postgresql`).
2. Insère, avant la première règle `host` existante, les deux lignes :
   ```
   hostssl all apanel all scram-sha-256
   host    all apanel all reject
   ```
   Idempotent (vérifie d'abord si déjà présent) — sans risque d'éditer le
   fichier pendant que Postgres tourne, il ne le relit qu'au démarrage ou sur
   `pg_reload_conf()`.
3. Recharge la config via `SELECT pg_reload_conf();` (pas de redémarrage du
   conteneur `postgresql`).

Se réexécute à chaque déploiement (comme les 2 autres conteneurs), donc
reste appliqué même si le volume `postgresql_data` est recréé de zéro.

## Connexion depuis Vercel

Voir `.env.prod` du repo `apanel` — `DATABASE_URL` avec
`sslmode=require` vers `pg-tcp.azteas.com:5432`, `REDIS_URL` en `rediss://`
vers `redis-tcp.azteas.com:6380`.
