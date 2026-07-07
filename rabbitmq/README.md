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
provisioning (conteneur one-shot) qui appelle l'API HTTP de gestion pour
créer son vhost, son user et ses permissions — idempotent, donc rejouable à
chaque déploiement (utile aussi pour la rotation de mot de passe).

Exemple complet et fonctionnel : voir `plane/docker-compose.yml`, service
`plane-mq-init`. Le schéma général :

```bash
curl -sf -u "$RABBITMQ_USER:$RABBITMQ_PASSWORD" -X PUT "http://rabbitmq:15672/api/vhosts/<service>"
curl -sf -u "$RABBITMQ_USER:$RABBITMQ_PASSWORD" -X PUT "http://rabbitmq:15672/api/users/<service>" \
  -H "content-type: application/json" \
  -d "{\"password\":\"<SERVICE_PASSWORD>\",\"tags\":\"\"}"
curl -sf -u "$RABBITMQ_USER:$RABBITMQ_PASSWORD" -X PUT "http://rabbitmq:15672/api/permissions/<service>/<service>" \
  -H "content-type: application/json" \
  -d '{"configure":".*","write":".*","read":".*"}'
```

Le service consomme ensuite RabbitMQ via :

```
AMQP_URL=amqp://<service>:<SERVICE_PASSWORD>@rabbitmq:5672/<service>
```

Le conteneur du service doit rejoindre le réseau `azteas-net` pour atteindre
l'hôte `rabbitmq`. Aucun port supplémentaire à exposer côté RabbitMQ.
