# RabbitMQ — File de messages partagée

Instance RabbitMQ unique, réutilisable par tous les services qui ont besoin
d'une file de tâches (Celery, workers, etc.). Le principe est le même que pour
`postgresql/` : une instance partagée, mais **un vhost + un user dédiés par
service consommateur** — jamais l'accès admin partagé.

## Accès

Dashboard de gestion : https://rabbitmq.azteas.com (login = `RABBITMQ_USER`/`RABBITMQ_PASSWORD`).

Ces identifiants sont réservés à :
- l'administration via le dashboard,
- le provisioning des vhosts/users des services consommateurs.

Aucune appli ne doit s'y connecter directement avec ces identifiants.

## Ajouter un nouveau service consommateur

Dans le `docker-compose.yml` du nouveau service, ajouter une étape de
provisioning (conteneur one-shot) qui crée son vhost, son user et ses
permissions — idempotent, donc rejouable à chaque déploiement (utile aussi
pour la rotation de mot de passe).

**Réutiliser l'image `rabbitmq:3.13-management-alpine` pour ce conteneur one-shot**
(même tag que le service `rabbitmq` ci-dessus, donc déjà présente sur le VPS —
aucun pull supplémentaire) en remplaçant son `entrypoint` par votre script :
elle embarque le CLI `rabbitmqadmin`, qui parle à l'API de gestion sans
dépendance externe (pas besoin d'une image `curl` séparée).

Exemple complet et fonctionnel : voir `plane/docker-compose.yml`, service
`plane-mq-init` (et `plane/init/mq-init.sh`). Le schéma général :

```bash
rabbitmqadmin --host=rabbitmq --username="$RABBITMQ_USER" --password="$RABBITMQ_PASSWORD" \
  declare vhost "name=<service>"

rabbitmqadmin --host=rabbitmq --username="$RABBITMQ_USER" --password="$RABBITMQ_PASSWORD" \
  declare user "name=<service>" "password=<SERVICE_PASSWORD>" "tags="

rabbitmqadmin --host=rabbitmq --username="$RABBITMQ_USER" --password="$RABBITMQ_PASSWORD" \
  declare permission "vhost=<service>" "user=<service>" "configure=.*" "write=.*" "read=.*"
```

Le service consomme ensuite RabbitMQ via :

```
AMQP_URL=amqp://<service>:<SERVICE_PASSWORD>@rabbitmq:5672/<service>
```

Le conteneur du service doit rejoindre le réseau `azteas-net` pour atteindre
l'hôte `rabbitmq`. Aucun port supplémentaire à exposer côté RabbitMQ.
