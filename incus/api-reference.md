# API REST Incus — créer et gérer des instances par programme

Référence pour piloter Incus par l'API REST plutôt qu'en CLI — c'est ce
qu'appellera apanel plus tard pour automatiser la création d'environnements
clients (voir `how-to-use-this-on-new-VDS.md`). Basé sur la documentation
officielle : [REST API](https://linuxcontainers.org/incus/docs/main/rest-api/),
[spécification complète](https://linuxcontainers.org/incus/docs/main/rest-api-spec/),
[authentification](https://linuxcontainers.org/incus/docs/main/authentication/).

⚠️ Les exemples de création/modification n'ont pas été testés contre un
serveur Incus réel (pas d'accès direct depuis cet environnement) — vérifier
chaque appel une fois avant de l'intégrer dans un script de production, en
particulier la section 6 (fusion des `devices`) qui est ma meilleure
compréhension de la doc plutôt qu'un exemple officiel confirmé.

## 1. Authentification

Incus authentifie les clients API par **certificat client TLS mutuel** —
le même mécanisme que le pairing du navigateur qu'on a fait pour l'UI, pas
un système différent. Deux choix :

- **Réutiliser le certificat `incus-ui`** déjà approuvé (`incus config
  trust list` doit le montrer) — fonctionne, mais mélange l'usage
  navigateur et automatisation sur un seul certificat.
- **Générer un certificat dédié pour l'automatisation** (recommandé) — se
  révoque indépendamment du certificat UI si une clé fuite un jour, sans
  casser l'accès au navigateur :
  ```bash
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 \
    -keyout apanel-api.key -out apanel-api.crt -days 3650 -nodes \
    -subj "/CN=apanel-api"

  scp apanel-api.crt hosting-vds:~/
  ssh hosting-vds "sudo incus config trust add-certificate ~/apanel-api.crt --name apanel-api"
  ```

Toutes les requêtes API s'authentifient ensuite avec ce certificat :
```bash
curl --cert apanel-api.crt --key apanel-api.key -k \
  https://<IP-du-VDS>:9443/1.0
```
Le `-k` accepte le certificat auto-signé du serveur Incus (voir
`incus/README.md` — remplacer par `--cacert` si le certificat serveur est
un jour remplacé par un certificat signé).

## 2. Créer une instance

`POST /1.0/instances` — équivalent API de la commande `incus launch` déjà
utilisée dans `how-to-use-this-on-new-VDS.md`.

```bash
curl --cert apanel-api.crt --key apanel-api.key -k -X POST \
  https://<IP-du-VDS>:9443/1.0/instances \
  -H "Content-Type: application/json" \
  -d '{
    "name": "client-exemple",
    "source": {
      "type": "image",
      "alias": "debian/12",
      "server": "https://images.linuxcontainers.org",
      "protocol": "simplestreams"
    },
    "config": {
      "limits.cpu": "2",
      "limits.memory": "4GiB",
      "user.plan": "dedie"
    },
    "devices": {
      "root": {
        "type": "disk",
        "path": "/",
        "pool": "default",
        "size": "20GiB"
      },
      "ssh-proxy": {
        "type": "proxy",
        "listen": "tcp:0.0.0.0:22002",
        "connect": "tcp:127.0.0.1:22"
      },
      "web-proxy": {
        "type": "proxy",
        "listen": "tcp:0.0.0.0:8002",
        "connect": "tcp:127.0.0.1:80"
      }
    }
  }'
```
`"server": "https://images.linuxcontainers.org"` avec
`"protocol": "simplestreams"` est ce que la CLI résout automatiquement
derrière l'alias `images:` — à préciser explicitement en API.

Cette requête ne crée l'instance que dans un état arrêté par défaut sauf
précision contraire selon la version — ajouter `"start": true` au corps
si l'instance doit démarrer immédiatement, sinon un second appel à
`PUT /1.0/instances/<name>/state` avec `{"action": "start"}` la démarre.

## 3. Suivre une opération (toutes les créations/modifications sont asynchrones)

La réponse à la création n'est **pas** le résultat final — Incus renvoie
`202 Accepted` avec une opération en cours :
```json
{"metadata": {"id": "ea6ac694-e325-442d-9cc2-ff55c64078a9", "status": "Running", "status_code": 103}}
```
Attendre la fin (bloquant) :
```bash
curl --cert apanel-api.crt --key apanel-api.key -k \
  https://<IP-du-VDS>:9443/1.0/operations/ea6ac694-e325-442d-9cc2-ff55c64078a9/wait
```
Un mainteneur Incus recommande d'appeler `/wait` **immédiatement** après
avoir reçu l'UUID — l'opération disparaît environ 5 secondes après avoir
atteint un état final, donc pas de délai avant de poller.

## 4. Modifier les limites d'une instance existante

`PATCH /1.0/instances/<nom>` modifie uniquement les clés fournies (ne
touche pas le reste de la config) — équivalent de `incus config set` :

```bash
curl --cert apanel-api.crt --key apanel-api.key -k -X PATCH \
  https://<IP-du-VDS>:9443/1.0/instances/client-exemple \
  -H "Content-Type: application/json" \
  -d '{"config": {"limits.cpu": "4", "limits.memory": "8GiB"}}'
```

Pour un remplacement complet de la config (plus risqué, écrase tout ce qui
n'est pas envoyé), utiliser `PUT` avec l'objet complet récupéré au
préalable via un `GET` et l'en-tête `If-Match` (ETag) — pas nécessaire pour
un simple ajustement de quota, `PATCH` suffit.

## 5. Ajouter un device (proxy) sur une instance existante

Pour exposer un nouveau port sur une instance déjà créée (équivalent
`incus config device add`) :
```bash
curl --cert apanel-api.crt --key apanel-api.key -k -X PATCH \
  https://<IP-du-VDS>:9443/1.0/instances/client-exemple \
  -H "Content-Type: application/json" \
  -d '{"devices": {"panel-proxy": {"type": "proxy", "listen": "tcp:0.0.0.0:8003", "connect": "tcp:127.0.0.1:8083"}}}'
```
Ma compréhension du comportement `PATCH` est qu'il fusionne cette entrée
dans la map `devices` existante sans supprimer les autres devices déjà
présents (`root`, `ssh-proxy`, etc.) — c'est le point le moins vérifié de
ce document, à confirmer avec un `GET` de l'instance juste après pour
s'assurer que rien d'autre n'a disparu.

## 6. Lister les instances et leur état

```bash
curl --cert apanel-api.crt --key apanel-api.key -k \
  "https://<IP-du-VDS>:9443/1.0/instances?recursion=2"
```
`recursion=2` renvoie les objets complets (config, devices, état
d'exécution) au lieu d'une simple liste d'URLs — utile pour construire un
tableau de bord de capacité (somme des `limits.memory`/`limits.cpu` déjà
engagés, cf. la convention `user.plan`/`user.ssh_port`/`user.http_port` de
`how-to-use-this-on-new-VDS.md`).

Filtrage possible côté serveur (syntaxe OData), ex. uniquement les
instances d'un plan donné :
```
?recursion=2&filter=config.user.plan eq "mutualise"
```

## 7. Équivalences CLI ↔ API (récapitulatif)

| Commande CLI (déjà utilisée dans les autres docs) | Appel API |
|---|---|
| `incus launch images:debian/12 <nom> -c limits.cpu=2 ...` | `POST /1.0/instances` |
| `incus config set <nom> limits.cpu=4` | `PATCH /1.0/instances/<nom>` |
| `incus config device add <nom> ...` | `PATCH /1.0/instances/<nom>` (clé `devices`) |
| `incus list` | `GET /1.0/instances?recursion=2` |
| `incus config trust add-certificate <fichier>` | `POST /1.0/certificates` (non vérifié dans ce document, voir note ci-dessous) |
| `incus exec <nom> -- <commande>` | `POST /1.0/instances/<nom>/exec` (WebSocket pour la sortie interactive, pas un simple appel HTTP — plus complexe, hors périmètre ici) |

## 8. Ce qui n'est pas couvert / à vérifier avant d'automatiser

- **Gestion des certificats de confiance par API** (`POST /1.0/certificates`,
  génération de token par API plutôt qu'en CLI) — mentionné dans la doc
  officielle mais je n'ai pas de shape de requête confirmée à donner ici.
  Utile si apanel doit un jour émettre ses propres tokens de pairing.
- **`incus exec` par API** est un mécanisme WebSocket (flux interactif),
  pas un appel REST classique — à documenter séparément le jour où c'est
  nécessaire (ex: lancer l'installation du panel automatiquement après
  création, plutôt que la commande manuelle `incus exec ... -- bash` +
  `wget`/`bash hst-install.sh` actuellement documentée).
- Comportement exact de `PATCH` sur `devices` (section 6) — à confirmer
  empiriquement.

Le passage de ces scripts manuels à une vraie automatisation (apanel
appelant cette API directement au moment où un client paie) reste une
étape non construite — ce document donne les briques, pas
l'orchestration complète.
