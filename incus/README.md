# Incus — Isolation clients (quotas SSD/RAM/CPU)

[Incus](https://linuxcontainers.org/incus/) gère des conteneurs système et
des VM avec des quotas durs (CPU, RAM, stockage). C'est la brique
d'isolation par client : chaque client obtiendra son propre conteneur Incus,
avec un quota de ressources dédié, dans lequel on installera ensuite un
panel d'hébergement pour qu'il héberge son site, crée sa base de données et
gère ses fichiers.

**Conteneurs uniquement, pas de VM sur ce VPS.** Contabo ne propose pas la
virtualisation imbriquée sur ses VPS (seulement sur ses offres VDS/dédié) —
sans elle, le mode VM d'Incus (qui a besoin de `/dev/kvm`) ne fonctionne
pas. Conséquence directe sur le choix du panel : **CloudPanel est écarté**
(non supporté officiellement en conteneur LXC, VM exigée) ; **HestiaCP est
le meilleur candidat** (retours d'expérience positifs en conteneur LXC non
privilégié) ; CyberPanel est possible mais a un historique plus cahoteux en
LXC (vérifications d'incompatibilité qu'il a fallu retirer côté projet).

## Portée de cette itération

Cette étape installe **uniquement** le démon Incus et son UI
d'administration sur `cpanel.azteas.com`. C'est un outil pour l'équipe
Azteas (créer/gérer les conteneurs/VM clients), **pas** une interface à
donner aux clients. La création automatisée d'environnements clients
(quotas par client, panel embarqué) est une itération future.

## Pourquoi ce dossier ne contient pas de `docker-compose.yml`

Contrairement aux autres services de ce repo, Incus n'est pas containerisé :
il gère lui-même des ponts réseau, des pools de stockage et les cgroups
directement sur l'hôte (c'est un hyperviseur/gestionnaire de conteneurs
système, pas une application). Le faire tourner nested dans Docker est
possible mais fragile (pas de VM sans passthrough `/dev/kvm`, perte de la
gestion native du stockage) — il est installé directement sur le VPS via le
dépôt APT officiel [Zabbly](https://github.com/zabbly/incus).

Conséquence sur le déploiement : `install.sh` s'exécute directement sur
l'hôte (SSH), comme `fail2ban/setup-fail2ban.sh` — pas de `docker compose
up`. L'action GitHub Actions ([deploy-incus.yml](../.github/workflows/deploy-incus.yml))
sync le dossier puis lance ce script, qui est idempotent : sans effet si
Incus est déjà installé et initialisé.

## Stockage : ZFS

Le pool de stockage par défaut est créé en ZFS (fichier loopback dimensionné
par `INCUS_STORAGE_SIZE`) — c'est le driver qui permet d'appliquer un quota
de taille par conteneur/VM plus tard (le driver `dir` ne le permet pas).
`install.sh` installe `zfsutils-linux` et vérifie que le module charge
avant de continuer ; si le noyau du VPS ne supporte pas ZFS nativement,
le script s'arrête avec une erreur explicite plutôt que de basculer
silencieusement sur un driver sans quota.

Le fichier loopback qui porte ce pool vit sur le disque déjà utilisé par
tous les autres services du VPS (Mailcow, bases partagées, Coolify,
Dokploy...) — ce n'est pas un disque séparé. Il est **sparse** (fichier
creux) : `INCUS_STORAGE_SIZE` fixe un plafond, pas une réservation
immédiate — l'espace disque réel n'est consommé qu'au fur et à mesure que
des données sont réellement écrites dedans par les futurs conteneurs
clients.

Contrairement au reste de la configuration Incus, cette taille n'est **pas**
figée après le premier déploiement : `install.sh` réapplique
`INCUS_STORAGE_SIZE` à chaque exécution (`incus storage set default size=...`),
donc changer la variable GitHub et redéployer suffit pour l'augmenter. Un
pool ZFS loop ne peut en revanche **jamais rétrécir automatiquement** — si
la valeur demandée est inférieure à la taille actuelle, Incus refuse le
changement, le script avertit et le pool reste inchangé (rien de destructif
n'est tenté). Réduire l'espace alloué demande une migration manuelle vers
un nouveau pool.

## Réseau : Traefik en TCP passthrough

L'API HTTPS d'Incus (port `8443`) utilise l'authentification mutuelle par
certificat client — Traefik ne peut pas terminer ce TLS et le relayer en
HTTP classique comme pour les autres services. Le routage suit donc le même
principe que `postgres`/`redis-tls` dans `traefik/traefik.yml` :
`traefik/dynamic/incus.yml` déclare un routeur **TCP** avec
`tls.passthrough: true`, basé sur `HostSNI` (le navigateur envoie le SNI dès
le ClientHello, donc pas besoin d'un entrypoint TCP dédié comme pour
Postgres — `cpanel.azteas.com` partage le port 443 avec le reste).

Incus tourne sur l'hôte, pas dans un conteneur Docker : `traefik/docker-compose.yml`
ajoute `extra_hosts: host.docker.internal:host-gateway` pour que le
conteneur Traefik puisse atteindre le port 8443 de l'hôte.

**Conséquence** : une route TCP passthrough ne passe pas par les
middlewares HTTP Traefik (`auth-basic`, `rate-limit-admin` — Traefik ne
supporte pas les middlewares HTTP sur les routeurs TCP). Le seul contrôle
d'accès est celui d'Incus lui-même (certificat client + token de pairing,
voir plus bas) — c'est un modèle différent du reste de l'infra, mais pas
plus faible : impossible de se connecter sans certificat approuvé, même en
atteignant le port.

## ⚠️ À vérifier après le premier déploiement (non testable depuis ce repo)

- Que le port `8443` n'est **pas** joignable depuis internet (seulement
  depuis le conteneur Traefik via `host.docker.internal`) :
  `sudo ufw status | grep 8443`. Si besoin, ajouter une règle `ufw deny
  8443/tcp` explicite — Docker manipule parfois iptables indépendamment
  d'ufw, donc à confirmer sur le VPS réel.
- Que le module ZFS se charge correctement sur le noyau du VPS Contabo
  (`install.sh` s'arrête proprement si ce n'est pas le cas, mais je n'ai
  pas pu le tester sur la machine réelle).
- Le nom exact du paquet `incus-ui-canonical` sur le dépôt Zabbly pour la
  version/distro effective du VPS.
- Qu'un enregistrement DNS `cpanel.azteas.com` existe bien et pointe vers
  l'IP du VPS. Le token Cloudflare (`CF_DNS_API_TOKEN`) sert uniquement au
  défi DNS-01 de Let's Encrypt dans Traefik — il ne crée aucun enregistrement
  DNS automatiquement. Si les autres sous-domaines (`*.azteas.com`) passent
  par un enregistrement générique, `cpanel` est probablement déjà couvert ;
  sinon il faut l'ajouter manuellement dans Cloudflare.

## Prérequis

Variable GitHub (Settings → Variables → Actions, pas un secret) :
- `INCUS_STORAGE_SIZE` — ex: `200GiB` (taille du pool ZFS, défaut `100GiB`
  si absente)

## Première connexion à l'UI

`https://cpanel.azteas.com` n'a **pas** le même comportement que les autres
sous-domaines admin (Traefik, pgAdmin, RabbitMQ...) : pas de certificat
Let's Encrypt (le passthrough ne passe pas par l'ACME de Traefik) et pas de
formulaire login/mot de passe. Deux étapes, dans l'ordre :

1. **Avertissement certificat.** Incus sert son propre certificat
   auto-signé sur le port 8443 — le navigateur affiche « connexion non
   privée » / cadenas barré. C'est attendu (comportement par défaut
   d'Incus, pas un bug de cette config) : cliquer sur *Avancé* → *Continuer*
   (Chrome/Edge) ou *Avancé* → *Accepter le risque et poursuivre* (Firefox).
   Se reproduit tant que le certificat par défaut n'est pas remplacé par un
   certificat signé (possible plus tard : voir `incus config set
   core.https_address`, mais pas fait dans cette itération).
2. **Pairing par token** (remplace le login classique — pas d'automatisation
   CI possible, ça nécessite de coller un token dans le navigateur) :
   ```bash
   ssh mailcow
   sudo incus config trust add admin
   # copier le token affiché, le coller sur l'écran de pairing de
   # https://cpanel.azteas.com (le navigateur génère alors son propre
   # certificat client et l'enregistre auprès d'Incus)
   ```

## Créer un environnement client (manuel pour l'instant)

Trois façons d'agir sur Incus : CLI (`incus ...` en SSH sur le VPS), l'UI
(`cpanel.azteas.com`, formulaire de création d'instance), ou l'API REST
directement (ce que CLI et UI utilisent toutes les deux en interne — c'est
ce qu'appellera plus tard apanel pour automatiser la création). Pour
l'instant, tout se fait à la main via CLI — le plus simple à reproduire de
façon fiable.

Incus ne connaît pas la notion de « panel » : on crée un conteneur avec une
image Linux nue et un quota, puis on installe le panel choisi dedans, comme
sur n'importe quel VPS neuf.

```bash
ssh mailcow

# 1. Créer le conteneur avec ses quotas CPU/RAM/disque
incus launch images:debian/12 client-<slug> \
  -c limits.cpu=2 \
  -c limits.memory=4GiB \
  -d root,size=20GiB

# 2. Entrer dedans
incus exec client-<slug> -- bash

# 3. À l'intérieur : installer le panel choisi (HestiaCP recommandé, voir
#    plus haut). Script officiel HestiaCP, générateur de commande sur
#    https://hestiacp.com/install.html :
wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh
bash hst-install.sh
```

Modifier les quotas d'un environnement existant (à chaud, sans recréer) :

```bash
incus config set client-<slug> limits.cpu=4
incus config set client-<slug> limits.memory=8GiB
incus config device set client-<slug> root size=40GiB
```

Le quota disque est appliqué par Incus/ZFS **en dehors** du conteneur — le
panel installé dedans n'a rien à configurer pour ça, il voit simplement un
disque de la taille allouée.

**Non résolu par cette itération** : rendre le panel du client joignable
depuis l'extérieur (device `proxy` Incus ou route Traefik dédiée par
client) et l'isolation réseau propre entre clients (OVN, voir plus haut) —
à traiter avant d'onboarder un vrai client, pas nécessaire pour tester la
création d'un environnement.

## Déploiement

```bash
./sync.sh incus
ssh mailcow
cd /opt/azteas-panel/incus
bash install.sh
```

Se réexécute à chaque déploiement sans effet si Incus est déjà installé et
initialisé (le pool de stockage n'est jamais recréé/écrasé une fois créé).
