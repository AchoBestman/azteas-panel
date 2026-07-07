# Minio — Stockage S3-compatible partagé

Instance Minio unique, réutilisable par n'importe quelle appli qui a besoin
de stocker des fichiers (uploads, pièces jointes, backups applicatifs, etc.)
via l'API S3. Même principe que `postgresql/` et `rabbitmq/` : une instance
partagée, mais **un bucket + un user/policy dédiés par appli consommatrice**.

## Accès

| Usage | URL | Identifiants |
|---|---|---|
| Console web (visualiser buckets, fichiers, users, policies) | https://minio.azteas.com | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`, ou les identifiants dédiés d'une appli (voir plus bas) |
| API S3 — accès interne (conteneurs sur `azteas-net`) | `http://minio:9000` | identifiants dédiés de l'appli |
| API S3 — accès externe (hors du docker host) | https://s3.azteas.com | identifiants dédiés de l'appli |

`MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` sont réservés à l'administration
(console complète + provisioning des nouvelles applis). Aucune appli ne doit
s'en servir directement.

## Principe : un bucket + un user par appli

Chaque appli consommatrice obtient :
- son propre **bucket** (nom = nom de l'appli, ex: `plane`)
- son propre **user Minio** (access key = nom de l'appli)
- sa propre **policy IAM**, qui ne l'autorise que sur son bucket

Ça isole les applis entre elles : si l'une est compromise, elle ne peut pas
lire/écrire/supprimer les fichiers d'une autre.

Un user dédié peut aussi se connecter à la console (avec son access
key/secret key à lui) pour visualiser uniquement son propre bucket — pas
besoin du compte root pour ça au quotidien.

## Ajouter une nouvelle appli interne (conteneur sur ce VPS)

Dans le `docker-compose.yml` de l'appli, ajouter une étape de provisioning
one-shot (idempotente, donc rejouable à chaque déploiement) qui utilise le
client `mc` avec les identifiants root pour créer bucket + user + policy.

**Réutiliser l'image `minio/minio:latest` pour ce conteneur one-shot** (même
tag que le service `minio` ci-dessus, donc déjà présente sur le VPS — aucun
pull supplémentaire) en remplaçant son `entrypoint` par votre script : le
binaire `mc` est déjà inclus dans l'image serveur, pas besoin de l'image
`minio/mc` séparée.

Exemple complet et fonctionnel : voir `plane/docker-compose.yml`, service
`plane-minio-init`. Schéma général :

```bash
mc alias set localminio http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb --ignore-existing localminio/<service>

cat > /tmp/policy.json << JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:*"],
    "Resource": ["arn:aws:s3:::<service>", "arn:aws:s3:::<service>/*"]
  }]
}
JSON

mc admin user add localminio <service> "<SERVICE_PASSWORD>"
mc admin policy create localminio <service>-policy /tmp/policy.json
mc admin policy attach localminio <service>-policy --user <service>
```

L'appli se connecte ensuite avec (variables au format générique
AWS/S3, compatibles avec la quasi-totalité des SDK) :

```
AWS_S3_ENDPOINT_URL=http://minio:9000
AWS_ACCESS_KEY_ID=<service>
AWS_SECRET_ACCESS_KEY=<SERVICE_PASSWORD>
AWS_S3_BUCKET_NAME=<service>
```

Le conteneur de l'appli doit rejoindre le réseau `azteas-net` pour atteindre
l'hôte `minio` directement (pas besoin de passer par Traefik/HTTPS en interne
— plus rapide, et rien à exposer publiquement).

## Connecter une appli externe (hors de ce VPS)

Utiliser l'endpoint public :

```
AWS_S3_ENDPOINT_URL=https://s3.azteas.com
AWS_ACCESS_KEY_ID=<service>
AWS_SECRET_ACCESS_KEY=<SERVICE_PASSWORD>
AWS_S3_BUCKET_NAME=<service>
```

Provisionner le bucket/user dédié une seule fois, en se connectant à Minio
depuis n'importe quelle machine avec `mc` :

```bash
mc alias set azteas-minio https://s3.azteas.com <MINIO_ROOT_USER> <MINIO_ROOT_PASSWORD>
mc mb --ignore-existing azteas-minio/<service>
# puis les mêmes commandes mc admin user/policy que ci-dessus, alias azteas-minio
```

### Point important : adressage "path-style"

Minio est configuré en mode **path-style only** (pas de sous-domaine par
bucket). Toujours indiquer explicitement ce mode côté client, sinon la
plupart des SDK essaient par défaut le style "virtual-hosted"
(`<bucket>.s3.azteas.com`), qui ne fonctionnera pas ici.

**Python (boto3) :**
```python
import boto3
from botocore.config import Config

s3 = boto3.client(
    "s3",
    endpoint_url="https://s3.azteas.com",
    aws_access_key_id="<service>",
    aws_secret_access_key="<SERVICE_PASSWORD>",
    config=Config(s3={"addressing_style": "path"}),
)
```

**AWS CLI :**
```bash
aws --endpoint-url https://s3.azteas.com s3 ls s3://<service>
```

**mc (client Minio) :** gère nativement le path-style, rien à configurer.

## Sécurité

- Ne jamais commiter de clé d'accès — voir `never-push-those.txt` à la racine du dépôt.
- Pour faire tourner un secret d'appli (`SERVICE_PASSWORD`), relancer l'étape
  de provisioning avec la nouvelle valeur : `mc admin user add` réinitialise
  le secret d'un user existant (idempotent).
- Les buckets sont privés par défaut (pas d'accès anonyme). Ne pas activer
  `mc anonymous set download` sauf besoin explicite de servir des fichiers
  publics sans authentification.
