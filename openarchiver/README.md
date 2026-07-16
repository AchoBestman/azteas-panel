# OpenArchiver — Archivage mail légal

[OpenArchiver](https://github.com/LogicLabs-OU/OpenArchiver) (image
`logiclabshq/open-archiver`) : plateforme d'archivage mail conforme
(Gmail/Google Workspace, Microsoft 365, PST, IMAP générique), avec recherche
plein texte et extraction du contenu des pièces jointes.

Déployé en remplacement pressenti de `piler/` (limitations rencontrées avec
Piler) — les deux cohabitent pour l'instant, `piler/` n'est pas retiré tant
qu'OpenArchiver n'a pas fait ses preuves en production.

Comme `plane/`, OpenArchiver **réutilise les services partagés** de ce
dépôt pour la base et le cache : `postgresql/`, `redis/`. Pour le stockage
des emails en revanche, **pas de `minio/`** : le choix s'est porté sur
**Cloudflare R2** (externe, hors de ce dépôt).

Pourquoi R2 plutôt que Minio partagé (comme Plane) : contrairement à Piler
qui écrit directement sur le Storage Box Hetzner monté
(`/mnt/storagebox/piler-store`), le Minio partagé de ce dépôt stocke sur le
disque du VPS (volume `minio_data`) — ce qui contredit le principe du repo
("VPS = compute only, stockage persistant externalisé") pour un archive mail
légal appelé à grossir sur des années. R2 règle ça : egress gratuit, aucune
croissance de disque VPS à gérer, durabilité gérée par Cloudflare (déjà
utilisé ici pour le DNS/ACME de `azteas.com`).

Meilisearch (recherche) et Apache Tika (extraction de texte) n'ont pas
d'équivalent partagé dans ce dépôt et sont donc dédiés, définis directement
dans `docker-compose.yml`, sans passer par des dossiers séparés.

## Dépendances

| Service | Utilisation |
|---|---|
| `postgresql/` (partagé) | Base `openarchiver`, role `openarchiver` |
| `redis/` (partagé) | File de tâches BullMQ — index `0` (voir note ci-dessous) |
| Cloudflare R2 (externe, pas `minio/`) | Bucket `openarchiver` (fichiers `.eml`) |
| Meilisearch (dédié) | Index de recherche plein texte |
| Apache Tika (dédié) | Extraction du texte des pièces jointes |

**`postgresql/` et `redis/` doivent déjà être déployés avant OpenArchiver**
(voir l'ordre de déploiement dans le `README.md` racine). Le bucket R2 se
crée indépendamment, côté Cloudflare (voir Prérequis ci-dessous).

## Classement des données archivées

OpenArchiver stocke chaque email/pièce jointe sous une clé S3 **basée sur
son hash SHA256** (déduplication + intégrité), pas sur un chemin lisible du
type `bucket/domaine/adresse@domaine/...`. Le classement par domaine/boîte
mail vit dans les métadonnées PostgreSQL et se fait via l'UI/la recherche,
pas via l'arborescence du bucket R2 — c'est le comportement par défaut de
l'appli, conservé tel quel (pas de configuration de chemin possible côté
`STORAGE_S3_*`).

> **Note Redis** : OpenArchiver ne documente pas de variable pour choisir un
> index logique Redis (`REDIS_HOST`/`REDIS_PORT`/`REDIS_PASSWORD` seulement).
> Il utilise donc l'index `0` (par défaut) de l'instance partagée, qui n'est
> pas revendiqué par un autre service — voir `redis/.env.example`.

## Provisioning automatique

Un conteneur one-shot (dossier `init/`) tourne à chaque déploiement et
crée/resynchronise les identifiants dédiés d'OpenArchiver sur PostgreSQL,
avant que l'appli ne démarre :

- `openarchiver-db-init` → crée la base + le role PostgreSQL `openarchiver`

Idempotent : sans effet si tout existe déjà, sauf resynchronisation du mot
de passe (il suffit de changer la valeur GitHub et redéployer).

Il utilise les identifiants **admin** du service partagé
(`POSTGRES_USER`/`PASSWORD`) uniquement pour ce provisioning — OpenArchiver
lui-même se connecte ensuite avec ses identifiants dédiés, jamais l'admin.

Le bucket R2 n'est **pas** provisionné automatiquement (pas d'équivalent au
`mc` de Minio pour R2 dans ce dépôt) — création manuelle unique requise, voir
Prérequis ci-dessous.

## Prérequis

### Cloudflare R2

1. Dashboard Cloudflare → R2 → créer un bucket, ex. `openarchiver`
2. R2 → API Tokens → créer un token avec permission **Object Read & Write**
   scopée à ce seul bucket (jamais un token compte-large)
3. Noter l'**Account ID** (visible dans l'URL du dashboard R2 ou la barre
   latérale Cloudflare) et les **Access Key ID / Secret Access Key** générés

Aucune règle de cycle de vie (lifecycle) à activer : c'est un archive légal,
les objets ne doivent jamais expirer automatiquement.

### Secrets et variables

Générer les secrets dédiés avant le premier déploiement :

```bash
openssl rand -hex 20      # OPENARCHIVER_DB_PASSWORD
openssl rand -hex 32      # OPENARCHIVER_MEILI_MASTER_KEY / OPENARCHIVER_ENCRYPTION_KEY
openssl rand -base64 32   # OPENARCHIVER_JWT_SECRET
```

Secrets GitHub à définir (Settings → Secrets → Actions, environnement `azteas-panel`) :
- `OPENARCHIVER_DB_PASSWORD`
- `OPENARCHIVER_R2_ACCESS_KEY_ID`
- `OPENARCHIVER_R2_SECRET_ACCESS_KEY`
- `OPENARCHIVER_MEILI_MASTER_KEY`
- `OPENARCHIVER_JWT_SECRET`
- `OPENARCHIVER_ENCRYPTION_KEY`

Variables GitHub à définir :
- `OPENARCHIVER_ARCHIVE_HOST` = `openarchiver.azteas.com`
- `OPENARCHIVER_R2_ACCOUNT_ID` = ID de compte Cloudflare
- `OPENARCHIVER_R2_BUCKET` (optionnelle, défaut `openarchiver` si absente)
- `OPENARCHIVER_VERSION` (optionnelle, défaut `latest` si absente)
- `OPENARCHIVER_SYNC_FREQUENCY` (optionnelle, cron 6 champs, défaut `0 0 */2 * * *`)

Les secrets/variables des services partagés (`POSTGRES_USER`,
`POSTGRES_PASSWORD`, `REDIS_PASSWORD`) doivent déjà exister dans GitHub
(créés lors du déploiement de `postgresql/`, `redis/`) — rien à ajouter pour
ceux-là.

## DNS

Ajouter un enregistrement A `openarchiver.azteas.com` pointant vers l'IP du
VPS (même procédure que les autres sous-domaines de ce dépôt) avant le
premier déploiement, pour que Let's Encrypt puisse émettre le certificat.

## Déploiement initial

```bash
./sync.sh openarchiver
ssh mailcow
cd /opt/azteas-panel/openarchiver
docker compose pull
docker compose up -d
docker compose ps
```

## Déploiement automatique

Tout push sur `main` modifiant `openarchiver/**` déclenche
`.github/workflows/deploy-openarchiver.yml`.

## Premier accès

Aller sur https://openarchiver.azteas.com et créer le premier compte
administrateur, puis configurer une source d'archivage (IMAP, Google
Workspace ou Microsoft 365).

## Sauvegardes

Les métadonnées (base `openarchiver`) sont couvertes par les dumps
PostgreSQL du service partagé. Les emails eux-mêmes (bucket R2
`openarchiver`) sont hors du périmètre de sauvegarde de ce dépôt : R2 est un
stockage managé externe avec sa propre durabilité — aucun job restic/backup
local ne le couvre ici. Si une redondance supplémentaire est requise
(versioning, réplication cross-région), ça se configure côté dashboard R2,
pas dans ce dépôt. L'index Meilisearch (volume `openarchiver_meili`) est
reconstructible depuis les données archivées et n'a pas besoin d'être
sauvegardé séparément.

## Ressources

- Documentation : https://docs.openarchiver.com
- Dépôt source : https://github.com/LogicLabs-OU/OpenArchiver
