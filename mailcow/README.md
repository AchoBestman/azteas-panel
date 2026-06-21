# Mailcow — Serveur mail

Mailcow s'installe dans `/opt/mailcow-dockerized` sur le VPS.
Ce dossier contient uniquement la configuration et les scripts de déploiement.

## Architecture

```
[Internet :443]
      ↓
[Traefik]  → mail.azteas.com → nginx-mailcow:8080
                                     ↓
                              [Mailcow stack]
                              postfix, dovecot, rspamd...

[Internet :25/465/587/993/4190]
      ↓ (direct, sans Traefik)
[postfix-mailcow / dovecot-mailcow]
```

Mailcow écoute en interne sur 8080/8443.
Traefik gère le SSL et route le trafic web vers Mailcow.
Les ports mail sont publiés directement par Mailcow.

## Fichiers

```
mailcow/
├── docker-compose.override.yml   # connecte nginx-mailcow à azteas-net + labels Traefik + certdumper
├── setup.sh                      # installation et configuration sur le VPS
├── setup-ufw.sh                  # règles UFW + ufw-docker pour les ports mail
├── .env.example
├── README.md
└── backup/
    ├── backup-mailcow.sh         # backup vers Backblaze B2 via restic
    ├── restore-from-b2.sh        # restauration depuis Backblaze B2
    ├── mailcow-backup.service    # unit systemd
    ├── mailcow-backup.timer      # timer systemd (4h00 quotidien)
    └── notify-failure.sh         # alerte email en cas d'échec
```

## Déploiement initial

### 1. Préparer le .env

```bash
cp .env.example .env
# Remplir toutes les valeurs
```

### 2. Depuis la machine locale

```bash
./sync.sh mailcow
```

### 3. Sur le VPS — Installation

```bash
ssh mailcow
cd /opt/azteas-panel/mailcow
bash setup.sh
```

Le script :
- Clone Mailcow dans `/opt/mailcow-dockerized`
- Configure les ports internes (8080/8443)
- Désactive Let's Encrypt interne et AUTODISCOVER_SAN
- Désactive IPv6
- Copie le `docker-compose.override.yml` (réseau azteas-net + certdumper)
- Installe le backup automatique (systemd timer, 4h00 quotidien → Backblaze B2)

### 4. Démarrer Mailcow

```bash
cd /opt/mailcow-dockerized
docker compose up -d
```

### 5. Configurer le pare-feu

```bash
cd /opt/azteas-panel/mailcow
bash setup-ufw.sh
```

Ce script configure :
- **UFW** (INPUT chain) : autorise les ports mail entrants
- **ufw-docker** (DOCKER-USER chain) : permet au trafic d'atteindre les conteneurs

> ⚠️ À exécuter **après** le démarrage de Mailcow — les conteneurs doivent exister pour ufw-docker.

### 6. DNS requis

| Enregistrement | Type | Valeur |
|----------------|------|--------|
| `mail.azteas.com` | A | IP VPS |
| `azteas.com` | MX | `mail.azteas.com` |
| `autoconfig.azteas.com` | CNAME | `mail.azteas.com` |
| `autodiscover.azteas.com` | CNAME | `mail.azteas.com` |
| `azteas.com` | TXT | `v=spf1 mx a -all` |
| `_dmarc.azteas.com` | TXT | `v=DMARC1; p=reject; rua=mailto:admin@azteas.com` |
| `dkim._domainkey.azteas.com` | TXT | Généré par Mailcow après démarrage |

## Ports mail — règles firewall

| Port | Protocole | Usage | Conteneur |
|------|-----------|-------|-----------|
| 25 | TCP | SMTP entrant | postfix-mailcow |
| 465 | TCP | SMTPS | postfix-mailcow |
| 587 | TCP | SMTP submission | postfix-mailcow |
| 993 | TCP | IMAPS | dovecot-mailcow |
| 4190 | TCP | ManageSieve | dovecot-mailcow |

## Backup

Backup automatique quotidien à 4h00 vers Backblaze B2 (via restic, chiffré).
Rétention : 7 jours, 4 semaines, 6 mois.

```bash
# Vérifier le dernier backup
sudo systemctl status mailcow-backup.timer

# Lancer manuellement
sudo systemctl start mailcow-backup.service

# Restaurer depuis Backblaze B2
cd /opt/azteas-panel/mailcow/backup
bash restore-from-b2.sh [SNAPSHOT_ID]
```

## Mise à jour Mailcow

```bash
cd /opt/mailcow-dockerized
bash update.sh
# Après mise à jour, ré-appliquer le override
cp /opt/azteas-panel/mailcow/docker-compose.override.yml .
docker compose up -d
```
