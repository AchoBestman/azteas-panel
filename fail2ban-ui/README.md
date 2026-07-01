# Fail2ban UI

Interface web pour gérer fail2ban sans passer par SSH : voir les jails et les IP bannies,
bannir/débannir une IP manuellement, gérer les jails/filtres, recevoir des notifications.

Image officielle [swissmakers/fail2ban-ui](https://github.com/swissmakers/fail2ban-ui).
fail2ban tourne directement sur l'hôte (voir [`../fail2ban`](../fail2ban)), pas en conteneur —
ce service s'y connecte localement via son socket de contrôle, monté en volume.

Routé comme les autres services du repo : branché sur `azteas-net`, découvert par Traefik via
labels Docker. Le seul écart est le port `8080` publié sur `127.0.0.1` de l'hôte — requis pour
que fail2ban (process hôte) puisse envoyer ses callbacks de ban/unban à l'UI ; ce port n'est
jamais exposé publiquement (bind explicite sur loopback).

## Authentification

**Aucune authentification native sans OIDC.** Cette infra n'a pas de fournisseur OIDC
(Keycloak/Authentik/Pocket-ID) configuré — l'accès est donc protégé **uniquement** par
`auth-basic@file` de Traefik (mêmes identifiants que le dashboard Traefik). Ne jamais retirer
ce middleware du router sans mettre en place une alternative.

## Prérequis sur le VPS

- fail2ban déjà installé et actif (`fail2ban/setup-fail2ban.sh`)
- Enregistrement DNS `fail2ban.azteas.com` → IP du VPS
- `auth-basic@file` configuré (`.htpasswd` déployé par `traefik/setup.sh`)

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
