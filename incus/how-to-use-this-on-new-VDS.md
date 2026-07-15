# Monter l'hébergement client sur un nouveau VDS — guide de A à Z

Runbook pour partir d'un VDS Contabo vierge et arriver à une plateforme
d'hébergement multi-client fonctionnelle : durcissement sécurité, Traefik,
Incus, deux modèles de client (mutualisé et dédié), routage HTTPS par
domaine, accès SSH par client.

**Ce nœud est volontairement séparé du VPS existant.** Mailcow, les bases
partagées, Coolify, Dokploy et le provisioning apanel restent sur le VPS
actuel — ce VDS ne sert qu'à l'hébergement client (Incus + les conteneurs
clients). Ça isole le blast radius (un incident chez un client ne touche
jamais le mail ou les bases internes) et ça donne un playbook reproductible
si un 3ᵉ nœud devient nécessaire plus tard.

## Sommaire

1. [Vue d'ensemble](#1-vue-densemble)
2. [Commander le VDS](#2-commander-le-vds)
3. [Durcissement de base](#3-durcissement-de-base-protections-vps)
4. [Docker et réseau](#4-docker-et-réseau)
5. [Traefik pour ce nœud](#5-traefik-pour-ce-nœud)
6. [Installer Incus](#6-installer-incus)
7. [Convention de ports et suivi des allocations](#7-convention-de-ports-et-suivi-des-allocations)
8. [Modèle mutualisé (pod CyberPanel)](#8-modèle-mutualisé-pod-cyberpanel)
9. [Modèle dédié (instance complète)](#9-modèle-dédié-instance-complète)
10. [Ajouter le domaine SSL d'un nouveau client](#10-ajouter-le-domaine-ssl-dun-nouveau-client)
11. [Checklist et ce qui reste manuel](#11-checklist-et-ce-qui-reste-manuel)

---

## 1. Vue d'ensemble

```
[Internet]
    │
    ▼
[Traefik — CE VDS]  ← IP unique, SSL par domaine (Let's Encrypt HTTP-01
    │                   pour les domaines clients, DNS-01/Cloudflare pour
    │                   cpanel.azteas.com)
    ├── HTTPS domaine-client-1.com ──┐
    ├── HTTPS domaine-client-2.com ──┼──► pod-01 (Incus, 1 CyberPanel,
    ├── HTTPS domaine-client-3.com ──┘     plusieurs comptes clients)
    │
    ├── HTTPS domaine-client-vip.com ────► client-vip (Incus, instance
    │                                       dédiée, CyberPanel/HestiaCP
    │                                       pour lui seul)
    │
    └── TCP passthrough cpanel.azteas.com ─► Incus UI (admin, équipe
                                                Azteas uniquement)
```

**Deux modèles de client, cohabitant sur le même VDS :**

| | Mutualisé (pod) | Dédié |
|---|---|---|
| Conteneur Incus | Partagé entre plusieurs clients | Un par client |
| Panel | 1 CyberPanel gère plusieurs comptes (packages) | 1 panel pour ce client seul |
| Isolation | Utilisateur Linux + cgroups (frontière CyberPanel) | Conteneur Incus complet (noyau/réseau/cgroups séparés) |
| Accès | SFTP scoped à son compte, pas de shell | SSH complet, root sur son conteneur |
| Coût par client | Faible (plusieurs clients par conteneur) | Élevé (quota dédié complet) |
| Usage | Offre standard | Offre premium / client privilégié |

Le choix SFTP-only pour le mutualisé n'est pas une limitation technique
arbitraire : donner un shell complet à plusieurs clients qui partagent le
même conteneur les mettrait dans le même bac à sable (même noyau, même
espace de processus) — c'est le modèle classique de l'hébergement
mutualisé (WHM/cPanel fonctionnent pareil).

**IP unique pour tout le monde.** Un seul VDS = une seule IP publique
partagée par tous les clients, mutualisés comme dédiés. Ça fonctionne pour
le web grâce au SNI/Host header (Traefik route par nom de domaine, pas par
IP — déjà le principe utilisé pour tout `*.azteas.com`). Pour SSH (pas de
notion de nom d'hôte dans le protocole), chaque instance qui a besoin d'un
accès shell reçoit un **port externe dédié** sur cette même IP unique (ex:
`ssh -p 22001 root@<IP-du-VDS>`).

---

## 2. Commander le VDS

- **Contabo VDS**, pas VPS — c'est le tier qui garantit des ressources
  dédiées (pas de survente par Contabo) et qui expose la virtualisation
  imbriquée (confirmé dans leur documentation officielle). Le VPS standard
  ne supporte ni l'un ni l'autre.
- **OS : Ubuntu 24.04 LTS** — cohérent avec le VPS existant, dépôt Zabbly
  (Incus) et `ufw-docker` testés dessus.
- Pas besoin d'IPv4 supplémentaire pour ce design (IP unique partagée).
  Si un jour tu veux vendre des IP dédiées à des clients premium, revoir
  la conversation sur le NIC `routed` et le bloc IPv6 /64.
- Première connexion : `ssh root@<IP-du-VDS>` avec le mot de passe fourni
  par Contabo (ou la clé si tu en as ajouté une à la commande).

---

## 3. Durcissement de base (protections VPS)

Mêmes principes que `scripts/init-vps.sh` et `fail2ban/` déjà en place sur
le VPS existant, adaptés à cette machine neuve. À exécuter en SSH sur le
VDS, dans l'ordre.

### 3.1 Utilisateur non-root

```bash
adduser azteas
usermod -aG sudo azteas
```

### 3.2 Durcissement SSH

```bash
# Choisir un port SSH non standard (remplace 2222 par ta valeur)
sudo sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config
sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Copier ta clé publique AVANT de couper le mot de passe, sinon tu te bloques dehors
ssh-copy-id -p 22 azteas@<IP-du-VDS>   # depuis ta machine locale, avant de redémarrer sshd

sudo systemctl restart sshd
```
⚠️ Teste la connexion sur le nouveau port dans un **second terminal** avant
de fermer la session actuelle — une erreur de config SSH sans session de
secours ouverte peut te bloquer dehors définitivement.

### 3.3 ufw — politique par défaut restrictive

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment "SSH"
sudo ufw allow 80/tcp comment "HTTP (Traefik, redirection HTTPS)"
sudo ufw allow 443/tcp comment "HTTPS (Traefik)"
sudo ufw enable
```

### 3.4 fail2ban

```bash
sudo apt-get update -q
sudo apt-get install -y fail2ban -q
sudo systemctl enable --now fail2ban
```
Jail SSH activée par défaut. Étendre plus tard aux logs Traefik/CyberPanel
une fois que le trafic réel arrive — même principe que
`fail2ban/jail.d/azteas.local.template` sur le VPS existant, pas recopié
tel quel ici car les chemins de logs diffèrent.

### 3.5 Mises à jour de sécurité automatiques

```bash
sudo apt-get install -y unattended-upgrades -q
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 3.6 Vérification

```bash
sudo ufw status verbose
sudo fail2ban-client status
sudo systemctl status ssh
```

---

## 4. Docker et réseau

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker azteas
# reconnexion SSH nécessaire pour que l'appartenance au groupe prenne effet

sudo ufw-docker install   # même outil que sur le VPS existant — Docker
                           # manipule iptables indépendamment d'ufw sans ça
docker network create hosting-net
```
`hosting-net` plutôt que `azteas-net` : nom différent volontairement, ce
sont deux machines physiques distinctes, pas de raison de laisser croire
qu'elles partagent un réseau.

---

## 5. Traefik pour ce nœud

Ce VDS a son **propre** Traefik, indépendant de celui du VPS existant.
Raison : les domaines clients sont des domaines **arbitraires** appartenant
aux clients (pas des sous-domaines `azteas.com`), donc le challenge ACME
DNS-01/Cloudflare déjà utilisé pour `azteas.com` ne s'applique pas — il
faut le challenge HTTP-01, déjà anticipé dans `traefik/traefik.yml` du VPS
existant (`letsencrypt-http`, commentée "pour les autres domaines, ex:
Hostinger") mais jamais encore utilisé. On réplique le même resolver ici.

Créer `/opt/hosting-vds/traefik/traefik.yml` :

```yaml
api:
  dashboard: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt-http
        options: default

certificatesResolvers:
  # cpanel.azteas.com — sous-domaine azteas.com, même compte Cloudflare
  # que le VPS existant (même token CF_DNS_API_TOKEN).
  letsencrypt:
    acme:
      email: "admin@azteas.com"
      storage: /letsencrypt/acme.json
      dnsChallenge:
        provider: cloudflare
        resolvers:
          - "1.1.1.1:53"
          - "8.8.8.8:53"
  # Domaines clients (arbitraires, pas dans la zone Cloudflare azteas.com)
  # — HTTP-01, nécessite que le port 80 soit joignable depuis internet et
  # que le client ait déjà pointé son domaine vers l'IP de ce VDS.
  letsencrypt-http:
    acme:
      email: "admin@azteas.com"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

providers:
  docker:
    exposedByDefault: false
    network: hosting-net
  file:
    directory: /etc/traefik/dynamic
    watch: true

log:
  level: INFO

accessLog:
  filePath: /var/log/traefik/access.log
  format: json
```

Créer `/opt/hosting-vds/traefik/docker-compose.yml` :

```yaml
services:
  traefik:
    image: traefik:v3.7
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    # Incus tourne sur l'hôte, pas dans un conteneur — nécessaire pour
    # atteindre son API en TCP passthrough (voir dynamic/incus.yml).
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic:/etc/traefik/dynamic:ro
      - letsencrypt:/letsencrypt
      - /var/log/traefik:/var/log/traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik-dashboard.rule=Host(`traefik-hosting.azteas.com`)"
      - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
      - "traefik.http.routers.traefik-dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
    networks:
      - hosting-net

networks:
  hosting-net:
    external: true

volumes:
  letsencrypt: {}
```

`CF_DNS_API_TOKEN` : le même token Cloudflare que sur le VPS existant
fonctionne (même zone `azteas.com`) — le copier dans un `.env` à côté,
jamais commité (mêmes règles que `never-push-those.txt`).

```bash
sudo mkdir -p /opt/hosting-vds/traefik/dynamic /var/log/traefik
cd /opt/hosting-vds/traefik
echo "CF_DNS_API_TOKEN=<valeur>" > .env
docker compose up -d
```

Mettre à jour le DNS Cloudflare : `cpanel.azteas.com` doit maintenant
pointer vers l'IP de **ce** VDS (pas celle de l'ancien VPS) — c'est là
qu'Incus va tourner.

---

## 6. Installer Incus

Réutilise exactement `incus/install.sh`, `incus/preseed.yml.template` et
`incus/.env.example` de ce repo — rien à réécrire, le script ne suppose
rien de spécifique à l'ancienne machine.

```bash
sudo mkdir -p /opt/azteas-panel/incus
sudo chown azteas:azteas /opt/azteas-panel/incus
```

Depuis ta machine locale (ajoute un alias SSH `hosting-vds` dans
`~/.ssh/config`, même principe que l'alias `mailcow` existant) :

```bash
rsync -avz incus/ hosting-vds:/opt/azteas-panel/incus/
ssh hosting-vds
cd /opt/azteas-panel/incus
echo "INCUS_STORAGE_SIZE=<taille selon le disque réel de ce VDS>" > .env
bash install.sh
```

Créer `/opt/hosting-vds/traefik/dynamic/incus.yml` (copie de
`traefik/dynamic/incus.yml` du VPS existant, port 9443 — pas besoin de
changer le port ici, ce VDS n'a pas de Mailcow qui occupe déjà 8443, mais
rester sur 9443 évite d'avoir deux conventions différentes à retenir) :

```yaml
tcp:
  routers:
    incus:
      rule: "HostSNI(`cpanel.azteas.com`)"
      entryPoints:
        - websecure
      tls:
        passthrough: true
      service: incus-svc
  services:
    incus-svc:
      loadBalancer:
        servers:
          - address: "host.docker.internal:9443"
```

Suivre ensuite `incus/README.md` (déjà dans ce repo) pour le pairing UI :
avertissement de certificat auto-signé, génération de certificat ou token,
import navigateur — procédure identique à celle déjà validée sur le VPS
existant.

---

## 7. Convention de ports et suivi des allocations

Un port externe unique par instance qui a besoin d'un accès direct
(SSH shell pour un dédié, ou SFTP pour un pod). Pas de registre séparé à
maintenir à la main : chaque port est tagué directement sur l'instance
Incus via `user.*`, consultable à tout moment avec `incus list`.

| Plage | Usage |
|---|---|
| `22001`–`22499` | SSH shell complet, instances dédiées |
| `22500`–`22999` | SFTP admin des pods (équipe Azteas uniquement) |
| `8001`–`8999` | Port web (HTTP) forwardé vers Traefik, un par instance (pod ou dédiée) |

```bash
# Exemple : after avoir créé une instance, taguer ses ports choisis
incus config set client-vip user.ssh_port "22001"
incus config set client-vip user.http_port "8001"
incus config set client-vip user.plan "dedie"

# Lister l'état de toutes les allocations
incus list -c n,m,limits.memory,limits.cpu,user.plan,user.ssh_port,user.http_port
```

---

## 8. Modèle mutualisé (pod CyberPanel)

### 8.1 Créer le pod

```bash
incus launch images:debian/12 pod-01 \
  -c limits.cpu=2 \
  -c limits.memory=8GiB \
  -d root,size=100GiB
incus config set pod-01 user.plan "mutualise"
```
Dimensionne le pod selon combien de clients légers tu comptes y mettre
(voir le calcul de densité vu précédemment — un pod 8G/2cores peut
raisonnablement accueillir 8-10 comptes clients légers selon leur trafic).

### 8.2 Installer CyberPanel dans le pod

```bash
incus exec pod-01 -- bash
```
Puis, dans le conteneur :
```bash
sh <(curl https://cyberpanel.net/install.sh || wget -qO - https://cyberpanel.net/install.sh)
```
CyberPanel a eu par le passé des vérifications qui bloquaient
l'installation en LXC — la communauté rapporte que ça fonctionne
aujourd'hui, mais teste ce pod avant d'y mettre un vrai client. Si
l'installeur refuse explicitement l'environnement conteneur, HestiaCP
reste le repli confirmé compatible LXC (voir la section modèle dédié).

### 8.3 Exposer le pod (un seul port web, CyberPanel route par domaine en interne)

```bash
# Depuis l'hôte (exit du conteneur d'abord)
incus config device add pod-01 web-proxy proxy \
  listen=tcp:0.0.0.0:8001 \
  connect=tcp:127.0.0.1:80
incus config device add pod-01 admin-ssh proxy \
  listen=tcp:0.0.0.0:22500 \
  connect=tcp:127.0.0.1:22
incus config set pod-01 user.http_port "8001"
incus config set pod-01 user.ssh_port "22500"
```
Un seul port web pour **tout le pod** — pas un par client dedans.
OpenLiteSpeed (le serveur web de CyberPanel) route déjà en interne par nom
de domaine, exactement comme Traefik le fait pour `*.azteas.com`. Chaque
nouveau client du pod n'ajoute qu'une entrée Traefik côté domaine (partie
10), pas un nouveau port.

Le port SSH admin (`22500`) reste réservé à l'équipe Azteas pour la
maintenance du pod — jamais donné à un client.

### 8.4 Ajouter un client dans le pod (CyberPanel)

Dans l'UI CyberPanel (`https://<IP-du-VDS>:8090` par défaut, ou en CLI) :

1. **Websites → Create Website** — associe le domaine du client, choisit
   le Package (voir étape suivante pour les quotas).
2. **Packages → Create Package** — fixe les limites du compte
   (disque, bande passante, nombre de DB, comptes email si besoin) avant
   de l'assigner au site.
3. **FTP → Create FTP Account** (ou onglet SFTP du site, selon version) —
   crée l'accès SFTP scopé au dossier du site, pas de shell complet. C'est
   l'« accès » que reçoit un client mutualisé.

Vérifie que le compte Linux créé pour ce client a bien un shell restreint
(`nologin` ou équivalent SFTP-only) — normalement le comportement par
défaut de CyberPanel pour un compte non-admin, mais à confirmer une fois
sur ce pod précis avant de généraliser.

---

## 9. Modèle dédié (instance complète)

Reprend exactement la procédure déjà documentée dans `incus/README.md`
(section "Créer un environnement client"), adaptée avec les ports de ce
VDS :

```bash
incus launch images:debian/12 client-<slug> \
  -c limits.cpu=2 \
  -c limits.memory=4GiB \
  -d root,size=20GiB \
  -c cloud-init.ssh-keys.client="root:<clé publique du client, optionnel>"
incus config set client-<slug> user.plan "dedie"

incus config device add client-<slug> ssh-proxy proxy \
  listen=tcp:0.0.0.0:22002 \
  connect=tcp:127.0.0.1:22
incus config device add client-<slug> web-proxy proxy \
  listen=tcp:0.0.0.0:8002 \
  connect=tcp:127.0.0.1:80
incus config set client-<slug> user.ssh_port "22002"
incus config set client-<slug> user.http_port "8002"
```

Installer HestiaCP (recommandé, compatibilité LXC confirmée) ou CyberPanel
en mode single-tenant à l'intérieur, comme déjà documenté. Ce client a un
accès SSH complet (`ssh -p 22002 root@<IP-du-VDS>`) et peut lui-même
ajouter sa propre clé plus tard depuis le panel (déjà vu : HestiaCP →
Compte → Manage SSH keys).

---

## 10. Ajouter le domaine SSL d'un nouveau client

Étapes identiques que le client soit dans un pod ou en dédié — seule la
cible (`user.http_port` de son pod ou de son instance) change.

1. **Le client pointe son domaine vers l'IP de ce VDS** (enregistrement A
   chez son propre registrar — hors de ton contrôle, à demander
   explicitement).
2. **Ajouter la route** avec `incus/add-client-domain.sh` (remplace
   l'écriture manuelle du fichier YAML — même résultat, sans risque de
   faute de frappe et rejouable) :
   ```bash
   ssh hosting-vds
   /opt/azteas-panel/incus/add-client-domain.sh add domaine-du-client.com <user.http_port de son pod/instance>
   ```
   Pour retirer un client (résiliation, changement de pod) :
   ```bash
   /opt/azteas-panel/incus/add-client-domain.sh remove domaine-du-client.com
   ```
3. Traefik surveille `dynamic/` (`watch: true`) — le fichier généré par le
   script est pris en compte automatiquement, pas besoin de redémarrer le
   conteneur.
4. **Premier accès HTTPS déclenche le challenge HTTP-01** — le certificat
   Let's Encrypt s'obtient automatiquement à la première requête, à
   condition que le DNS du client pointe déjà vers ce VDS (étape 1) et que
   le port 80 soit ouvert (déjà fait, partie 3.3).
5. Vérifier : `docker logs traefik | grep <domaine-du-client>` doit
   montrer l'obtention du certificat sans erreur.

Le script vit dans `incus/` et se déploie avec le reste (`rsync -avz incus/
hosting-vds:/opt/azteas-panel/incus/`, comme pour `install.sh`) — pas
besoin de le copier à part.

---

## 11. Checklist et ce qui reste manuel

- [ ] VDS commandé, OS Ubuntu 24.04, virtualisation imbriquée confirmée
- [ ] Durcissement (partie 3) appliqué et vérifié
- [ ] Docker + `ufw-docker` + réseau `hosting-net`
- [ ] Traefik de ce nœud démarré, dashboard accessible
- [ ] `cpanel.azteas.com` repointé en DNS vers ce VDS
- [ ] Incus installé, pairing UI fait
- [ ] Au moins un pod de test + un dédié de test créés et vérifiés
      (CyberPanel en LXC en particulier — confirmer avant de généraliser)

**Non automatisé volontairement à ce stade** (cohérent avec le reste de ce
dossier `incus/` — v1 = manuel/scripté en local, orchestration complète
via apanel plus tard) :
- Création de compte CyberPanel/package par client mutualisé (partie 8.4) —
  toujours manuel via l'UI CyberPanel, pas encore scripté.
- Suivi de la capacité restante par pod/nœud (partie 7 donne le mécanisme
  de tag, mais aucun script n'alerte automatiquement quand un pod est
  plein).
- Isolation réseau fine entre clients d'un même pod (OVN, déjà noté comme
  amélioration future dans `incus/README.md` — non nécessaire tant que
  l'isolation par utilisateur Linux + cgroups de CyberPanel suffit).

Quand ce VDS approche de sa capacité (voir le calcul de densité RAM/CPU
déjà fait), le même guide se rejoue pour un nœud supplémentaire — change
juste le nom du réseau Docker et les plages de ports pour éviter toute
confusion entre nœuds.
