# Azteas Panel

Infrastructure complète de services auto-hébergés sur VPS, orientée usage commercial.
Chaque service est isolé dans son propre conteneur Docker et géré indépendamment.

## Architecture globale

```
[Internet]
     ↓
[Traefik]  ← reverse proxy central, SSL automatique via Let's Encrypt
     ↓
┌─────────────────────────────────────────────────────┐
│                  Réseau Docker : azteas-net          │
├──────────┬──────────┬────────────┬──────────────────┤
│  Traefik │  Piler   │  MariaDB   │  PostgreSQL      │
│  Mailcow │  MongoDB │  Redis     │  pgAdmin         │
│          │ phpMyAdmin│ MongoExpress│  ...            │
└──────────┴──────────┴────────────┴──────────────────┘
                          ↓
              Stockage externe (Hetzner Storage Box)
                          ↓
                 Backup froid (Backblaze B2)
```

**Principe** : le VPS est dédié au compute (RAM, CPU, bande passante). Le stockage persistant est externalisé sur Hetzner Storage Box. Backblaze B2 assure le backup froid quotidien.

## Structure du projet

```
azteas-panel/
├── .env.example              # variables globales (copier en .env, ne jamais commiter)
├── .gitignore
├── never-push-those.txt      # règles de sécurité — lire avant tout commit
├── sync.sh                   # envoi manuel vers le VPS
├── scripts/
│   └── clean-vps.sh          # documentation nettoyage VPS
├── traefik/                  # reverse proxy + SSL (à déployer en premier)
├── piler/                    # archivage mail
├── mailcow/                  # serveur mail
├── mariadb/                  # base de données MariaDB
├── postgresql/               # base de données PostgreSQL
├── mongodb/                  # base de données MongoDB
├── redis/                    # cache Redis
└── ...
```

Chaque dossier de service contient :
- `docker-compose.yml`
- `.env.example`
- `README.md` (instructions spécifiques au service)
- `.github/workflows/deploy.yml` (GitHub Action de déploiement)

## Sécurité — règle absolue

Aucune clé, mot de passe ou secret ne doit jamais être commité.
Lire [`never-push-those.txt`](never-push-those.txt) avant tout commit.

Toutes les valeurs sensibles sont définies dans `.env` (ignoré par git).
Copier `.env.example` en `.env` et remplir les valeurs réelles.

## Prérequis locaux

- `rsync` installé
- Alias SSH `mailcow` configuré dans `~/.ssh/config` :

```
Host mailcow
    HostName <IP_VPS>
    User <USER>
    Port <PORT>
    IdentityFile ~/.ssh/id_ed25519
```

## Déploiement

### Envoi manuel vers le VPS

```bash
# Sync complet
./sync.sh

# Sync d'un seul service
./sync.sh traefik
./sync.sh piler
./sync.sh mariadb
```

### Déploiement automatique

Chaque service possède sa propre GitHub Action dans `.github/workflows/`.
Les actions se déclenchent indépendamment sur push dans le dossier du service concerné.

Secrets GitHub Actions à définir dans les Settings du dépôt :
- `VPS_HOST`
- `VPS_USER`
- `VPS_PORT`
- `VPS_SSH_PRIVATE_KEY`

## Ordre de déploiement initial

1. **Nettoyage VPS** → suivre `scripts/clean-vps.sh`
2. **Traefik** → fondation de l'infrastructure (réseau + SSL)
3. **Mailcow** → serveur mail
4. **Piler** → archivage mail (dépend de Mailcow pour le BCC)
5. **Bases de données** → MariaDB, PostgreSQL, MongoDB, Redis
6. **Interfaces admin** → pgAdmin, phpMyAdmin, MongoExpress

## Stockage

| Destination | Usage |
|-------------|-------|
| VPS Contabo | Compute uniquement (RAM, CPU, bande passante) |
| Hetzner Storage Box | Données persistantes (mail store, DB dumps, uploads) |
| Backblaze B2 | Backup froid quotidien automatisé |

## Domaine

Domaine principal : `azteas.com`

| Sous-domaine | Service |
|--------------|---------|
| `mail.azteas.com` | Mailcow |
| `archive.azteas.com` | Piler |
| `traefik.azteas.com` | Dashboard Traefik (accès restreint) |
| `db.azteas.com` | pgAdmin |
| `mongo.azteas.com` | MongoExpress |
| `f2b.azteas.com` | Fail2ban UI |
