# Fail2ban UI

Interface web pour gérer fail2ban sans passer par SSH : voir les jails et les IP bannies,
bannir/débannir une IP manuellement, gérer les jails/filtres, recevoir des notifications.

Image officielle [swissmakers/fail2ban-ui](https://github.com/swissmakers/fail2ban-ui).
fail2ban tourne directement sur l'hôte (voir [`../fail2ban`](../fail2ban)), pas en conteneur —
ce service s'y connecte localement via son socket de contrôle.

## Particularités de cette image

- **`network_mode: host` obligatoire** pour parler au fail2ban de l'hôte (socket local +
  espace de noms réseau partagé). Impossible donc de la brancher sur `azteas-net` avec des
  labels Traefik classiques : le routage se fait via
  [`../traefik/dynamic/fail2ban-ui.yml`](../traefik/dynamic/fail2ban-ui.yml), qui pointe vers
  `http://host.docker.internal:8080` (route ajoutée dans `traefik/docker-compose.yml` via
  `extra_hosts: host-gateway`).
- **Aucune authentification native sans OIDC.** Cette infra n'a pas de fournisseur OIDC
  (Keycloak/Authentik/Pocket-ID) configuré — l'accès est donc protégé **uniquement** par
  `auth-basic@file` de Traefik (mêmes identifiants que le dashboard Traefik). Ne jamais
  déployer ce service sans cette protection.
- **Port 8080 exposé sur toutes les interfaces de l'hôte** (conséquence du `network_mode: host`
  + `BIND_ADDRESS=0.0.0.0`, nécessaire pour que Traefik puisse l'atteindre). **Le firewall du
  VPS doit bloquer le port 8080 depuis l'extérieur** (seuls 80/443 doivent être publics) :
  ```bash
  sudo ufw deny 8080
  ```

## Prérequis sur le VPS

- fail2ban déjà installé et actif (`fail2ban/setup-fail2ban.sh`)
- Enregistrement DNS `f2b.azteas.com` → IP du VPS
- `auth-basic@file` configuré (`.htpasswd` déployé par `traefik/setup.sh`)
- Port 8080 bloqué depuis l'extérieur par le firewall (voir ci-dessus)
- Traefik redéployé après le premier push (pour prendre en compte `extra_hosts` et le nouveau
  fichier dynamic) — se fait automatiquement via `deploy-traefik.yml`

## Sécurité

- Accès protégé par l'authentification basique Traefik (`auth-basic@file`) + rate limiting
- La jail `fail2ban-ui-auth` (voir `../fail2ban`) bannit les IP qui échouent l'authentification
- Voir la [doc sécurité upstream](https://github.com/swissmakers/fail2ban-ui/blob/main/docs/security.md)
  et [reverse-proxy upstream](https://github.com/swissmakers/fail2ban-ui/blob/main/docs/reverse-proxy.md)

## Déploiement

Automatique via `.github/workflows/deploy-fail2ban-ui.yml` sur push dans `fail2ban-ui/**`.

Manuel :
```bash
./sync.sh fail2ban-ui
ssh mailcow 'cd /opt/azteas-panel/fail2ban-ui && docker compose pull && docker compose up -d'
```
