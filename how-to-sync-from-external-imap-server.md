# Synchronisation IMAP depuis un serveur externe vers Mailcow

Ce guide explique comment migrer ou synchroniser des emails depuis un serveur mail externe vers Mailcow via l'interface **Configuration → Sync Jobs**.

## Accès

Mailcow → **Configuration → Sync Jobs → Add sync job**

## Champs du formulaire

### Informations de connexion

| Champ | Description |
|-------|-------------|
| **Username** | Email de destination sur Mailcow (ex: `admin@azteas.com`) |
| **Host** | Adresse du serveur IMAP source (ex: `imap.gmail.com`) |
| **Port** | Port IMAP du serveur source (`993` pour SSL, `143` pour STARTTLS) |
| **Username** | Identifiant sur le serveur source |
| **Password** | Mot de passe sur le serveur source (stocké en clair) |
| **Encryption** | `SSL` pour port 993, `STARTTLS` pour port 143 |

### Options de synchronisation

**Polling interval (minutes)**
Fréquence à laquelle Mailcow vérifie le serveur source pour de nouveaux emails.
- `20` = vérification toutes les 20 minutes
- Pour une migration ponctuelle, mettre une valeur faible (ex: `1`) puis désactiver le job une fois terminé

**Sync into subfolder**
Si rempli, tous les emails copiés seront placés dans un sous-dossier.
- Vide = emails intégrés directement dans les dossiers Mailcow (INBOX, Sent, etc.)
- `OldServer` = crée `OldServer/INBOX`, `OldServer/Sent`, etc.
- Utile pour ne pas mélanger anciens et nouveaux emails

**Maximum age of messages in days**
- `0` = copie toute l'historique sans limite d'âge
- `30` = copie uniquement les emails des 30 derniers jours
- Utile pour les grandes boîtes mail : commencer par les récents, puis élargir

**Max. bytes per second**
- `0` = illimité
- Ex: `1000000` = limite à 1 MB/s pour ne pas saturer la bande passante

**Timeout for connection to remote host**
Délai d'attente max (en secondes) pour la connexion au serveur source.
- Défaut : `600` (10 minutes)
- Augmenter si le serveur source est lent ou distant

**Timeout for connection to local host**
Délai d'attente max pour la connexion à Mailcow lui-même.
- Défaut : `600`

**Exclude objects (regex)**
Dossiers à ignorer lors de la synchronisation (expressions régulières).
- Défaut : `(?i)spam|(?i)junk` — ignore les dossiers Spam et Junk
- Exemples : `(?i)trash` pour ignorer la corbeille

**Custom parameters**
Options avancées passées directement à imapsync en ligne de commande.
- Format correct : `--param=valeur`
- Format incorrect : `--param valeur`

### Options avancées (cases à cocher)

| Option | Description |
|--------|-------------|
| **Delete duplicates on destination** `--delete2duplicates` | Supprime les doublons sur Mailcow si le même email est présent deux fois |
| **Delete from source when completed** `--delete1` | Supprime les emails du serveur source après copie — ⚠️ migration destructive, irréversible |
| **Delete messages on destination not on source** `--delete2` | Maintient Mailcow en miroir exact de la source — ⚠️ supprime ce qui n'est pas sur la source |
| **Automap folders** `--automap` | Mappe automatiquement les noms de dossiers équivalents ("Sent Items" → "Sent", etc.) — recommandé |
| **Skip cross duplicates** `--skipcrossduplicates` | Si un email existe dans plusieurs dossiers, ne le copie qu'une fois (premier arrivé) |
| **Subscribe all folders** `--subscribeall` | Abonne automatiquement le client mail à tous les dossiers copiés |
| **Simulate** `--dry` | Simule la synchronisation sans rien modifier — **toujours tester d'abord** |

## Procédure recommandée pour une migration

1. **Tester d'abord** avec `--dry` activé pour voir ce qui sera synchronisé
2. Désactiver `--dry` et lancer la migration réelle
3. Activer `--automap` pour le mapping automatique des dossiers
4. Une fois la migration terminée, désactiver ou supprimer le sync job

## Cas d'usage

- Migration depuis Gmail, Outlook, un ancien serveur Postfix, etc.
- Synchronisation continue d'une boîte secondaire vers Mailcow
- Consolidation de plusieurs comptes en un seul

## Comprendre le résultat du mode --dry

Le mode simulation (`--dry`) ne modifie rien mais affiche exactement ce qui se passerait. Voici comment lire les statistiques :

```
Folders synced          : 4/4 synced          → 4 dossiers détectés et prêts à migrer
Messages transferred    : 0 (could be 8 ...)  → 8 messages seraient copiés en mode réel
Messages found in host1 not in host2 : 0      → messages présents sur la source mais pas sur Mailcow
Messages found in host2 not in host1 : 0      → messages présents sur Mailcow mais pas sur la source
Detected 0 errors                             → aucune erreur de connexion ou de configuration
```

**Note importante sur --dry et les sous-dossiers :**
Si tu utilises `Sync into subfolder`, le dry-mode ne peut pas simuler le contenu des messages car les sous-dossiers n'existent pas encore sur Mailcow. Il affichera :
```
Since --dry mode is on and folder [...] does not exist yet, syncing messages will not be simulated.
```
C'est normal. Pour simuler complètement avec sous-dossiers :
1. Lancer d'abord `--justfolders` sans `--dry` pour créer les dossiers
2. Puis relancer avec `--dry` pour simuler le contenu

**Pour passer en migration réelle :**
Dans Mailcow, éditer le sync job et décocher **Simulate synchronization (--dry)**, puis sauvegarder.
La migration démarrera au prochain polling interval.

## Comportement du polling et des jobs

**Recharger la page n'annule pas le job** — le sync job est persistant en base de données. Il tourne en arrière-plan selon le polling interval défini, que tu sois connecté ou non à l'interface Mailcow.

**Comportement du polling interval :**
1. Toutes les N minutes (ex: 20), Mailcow lance une exécution imapsync
2. Si le job précédent est encore en cours, il attend qu'il se termine avant d'en lancer un nouveau — pas de double exécution simultanée
3. Une fois terminé, il attend les N prochaines minutes avant de relancer

**Première vs exécutions suivantes :**
- **Première exécution** — peut prendre de quelques secondes à plusieurs heures selon le volume d'emails à migrer
- **Exécutions suivantes** — quasi-instantanées, imapsync ne recopie que les nouveaux messages (il conserve un état des emails déjà synchronisés via les headers ajoutés)

**Suivre l'état d'un job :**

Dans Mailcow → **Configuration → Sync Jobs** :
- La liste affiche la date/heure de la dernière exécution et son statut
- Bouton **Logs** (icône) → détails complets de la dernière exécution (messages copiés, erreurs, statistiques)
- Bouton **Run now** (icône play) → force une exécution immédiate sans attendre le prochain polling

## Notes de sécurité

⚠️ Les mots de passe sont stockés en clair dans Mailcow — utiliser un mot de passe d'application dédié si le service source le propose (Gmail, Outlook).
