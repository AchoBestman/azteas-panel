# Traefik — Reverse proxy central

Point d'entrée unique de toute l'infrastructure azteas-panel.
Gère SSL automatique via Let's Encrypt et route le trafic vers chaque service.

## Rôle

- Ecoute sur les ports 80 (redirect HTTPS) et 443
- Génère et renouvelle les certificats SSL automatiquement
- Expose le réseau Docker `azteas-net` partagé par tous les services
- Protège le dashboard et les interfaces admin via auth HTTP basique

## Structure

```
traefik/
├── docker-compose.yml
├── traefik.yml              # configuration statique
├── dynamic/
│   ├── middlewares.yml      # auth-basic, secure-headers, rate-limit
│   └── .htpasswd            # généré par setup.sh (non commité)
├── letsencrypt/
│   └── acme.json            # certificats SSL (non commité)
├── setup.sh                 # à exécuter sur le VPS une seule fois
├── .env.example
└── .github/workflows/
    └── deploy.yml
```

## Déploiement initial

### 1. Depuis la machine locale

```bash
./sync.sh traefik
```

### 2. Sur le VPS

```bash
ssh mailcow
cd /opt/azteas-panel/traefik
bash setup.sh
```

Le script génère :
- `letsencrypt/acme.json` (permissions 600)
- `dynamic/.htpasswd` (mot de passe dashboard)
- `.env` (non commité)

### 3. Démarrer Traefik

```bash
docker compose up -d
docker compose logs -f
```

### 4. Vérifier

```bash
docker compose ps
```

Accès dashboard : https://traefik.azteas.com (user/password définis dans setup.sh)

## Déploiement automatique

Tout push sur `main` modifiant `traefik/**` déclenche la GitHub Action, qui régénère et
redéploie `.env` **et** `dynamic/.htpasswd` à chaque exécution — plus besoin de relancer
`setup.sh` sur le VPS après le tout premier déploiement.

Secrets GitHub requis (Settings → Secrets → Actions) :
- `VPS_HOST`
- `VPS_PORT`
- `VPS_USER`
- `VPS_SSH_PRIVATE_KEY`
- `CF_DNS_API_TOKEN`
- `TRAEFIK_DASHBOARD_AUTH` — ligne htpasswd **brute, non échappée** (ex.
  `admin:$2y$05$abcdefghijklmnopqrstuv...`), générée via
  `htpasswd -nbB <user> <password>` ou affichée par `setup.sh` en fin d'exécution.
  Utilisée pour le dashboard Traefik et tous les services derrière `auth-basic@file`
  (ex. fail2ban-ui).

Variable GitHub requise :
- `ACME_EMAIL`

## Réseau partagé

Tous les services qui doivent être exposés via Traefik rejoignent le réseau `azteas-net` :

```yaml
networks:
  azteas-net:
    external: true
    name: azteas-net
```

## Ajouter un nouveau service

Ajouter ces labels dans le `docker-compose.yml` du service :

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.MON_SERVICE.rule=Host(`monservice.azteas.com`)"
  - "traefik.http.routers.MON_SERVICE.entrypoints=websecure"
  - "traefik.http.routers.MON_SERVICE.tls.certresolver=letsencrypt"
  - "traefik.http.routers.MON_SERVICE.middlewares=secure-headers@file"
```
