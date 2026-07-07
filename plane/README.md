# Plane — Gestionnaire de projet

[Plane](https://plane.so) (Community Edition), déployé via l'image officielle
**All-In-One** (`makeplane/plane-aio-community`), qui regroupe dans un seul
conteneur : web app, espaces publics, panneau admin (« god-mode »), API,
serveur temps réel (live/collaboration), workers et proxy interne (Caddy).

Contrairement à `coolify/` (qui a sa propre base/redis dédiées), Plane
**réutilise les services partagés** de ce dépôt : `postgresql/`, `redis/`,
`rabbitmq/`, `minio/`. Il n'installe rien lui-même — seuls des identifiants
dédiés à Plane sont créés sur ces services partagés au déploiement.

## Dépendances

| Service partagé | Utilisation par Plane |
|---|---|
| `postgresql/` | Base `plane`, role `plane` |
| `redis/` | Cache/sessions, index logique `1` |
| `rabbitmq/` | Vhost `plane`, user `plane` (file de tâches worker/beat) |
| `minio/` | Bucket `plane`, user `plane` (fichiers/pièces jointes) |

**Ces 4 services doivent déjà être déployés avant Plane** (voir l'ordre de
déploiement dans le `README.md` racine).

## Provisioning automatique

Trois conteneurs one-shot (dossier `init/`) tournent à chaque déploiement et
créent/resynchronisent les identifiants dédiés de Plane sur les services
partagés, avant que l'appli ne démarre :

- `plane-db-init` → crée la base + le role PostgreSQL `plane`
- `plane-mq-init` → crée le vhost + le user RabbitMQ `plane`
- `plane-minio-init` → crée le bucket + le user/policy Minio `plane`

Idempotents : sans effet si tout existe déjà, sauf resynchronisation du mot
de passe (utile pour faire tourner un secret — il suffit de changer la
valeur GitHub et redéployer).

Ils utilisent les identifiants **admin** des services partagés
(`POSTGRES_USER`/`PASSWORD`, `RABBITMQ_USER`/`PASSWORD`,
`MINIO_ROOT_USER`/`PASSWORD`) uniquement pour ce provisioning — Plane
lui-même se connecte ensuite avec ses identifiants dédiés, jamais les admin.

## Prérequis

Générer les secrets dédiés à Plane avant le premier déploiement :

```bash
openssl rand -hex 32   # PLANE_SECRET_KEY
openssl rand -hex 32   # PLANE_LIVE_SECRET_KEY
openssl rand -hex 20   # PLANE_DB_PASSWORD / PLANE_RABBITMQ_PASSWORD / PLANE_MINIO_PASSWORD
```

Secrets GitHub à définir (Settings → Secrets → Actions, environnement `azteas-panel`) :
- `PLANE_DB_PASSWORD`
- `PLANE_RABBITMQ_PASSWORD`
- `PLANE_MINIO_PASSWORD`
- `PLANE_SECRET_KEY`
- `PLANE_LIVE_SECRET_KEY`

Variable GitHub optionnelle :
- `PLANE_VERSION` (défaut `stable` si absente)

Les secrets/variables des services partagés (`POSTGRES_USER`,
`POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `RABBITMQ_USER`, `RABBITMQ_PASSWORD`,
`MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`) doivent déjà exister dans GitHub
(créés lors du déploiement de `postgresql/`, `redis/`, `rabbitmq/`, `minio/`)
— rien à ajouter pour ceux-là, le workflow de Plane les réutilise tels quels.

## Déploiement initial

```bash
./sync.sh plane
ssh mailcow
cd /opt/azteas-panel/plane
docker compose pull
docker compose up -d
docker compose ps
```

Toutes les migrations de base de données s'exécutent automatiquement au
démarrage du conteneur `plane` (processus `migrator` interne, avant l'API).

## Déploiement automatique

Tout push sur `main` modifiant `plane/**` déclenche `.github/workflows/deploy-plane.yml`.

## Premier accès

Aller sur https://plane.azteas.com et créer le premier compte : il devient
automatiquement administrateur de l'instance (accès au panneau « god-mode »).

## Sauvegardes

L'état persistant de Plane vit désormais dans les services partagés — donc
couvert par leurs propres sauvegardes respectives (base `plane` dans les
dumps PostgreSQL, bucket `plane` dans les données Minio). Rien de spécifique
à sauvegarder côté dossier `plane/` lui-même (les volumes `plane_logs` et
`plane_data` ne contiennent que logs et cache, pas de données utilisateur).

## Notes

- `USE_MINIO=0` dans le `docker-compose.yml` est normal : l'image AIO force
  cette valeur en interne (voir `start.sh` de l'image) et route le stockage
  Minio via les variables `AWS_S3_*` génériques, pas via ce flag.
