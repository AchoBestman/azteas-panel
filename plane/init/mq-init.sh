#!/bin/sh
set -eu

# Le healthcheck du service rabbitmq garantit que l'AMQP répond, pas
# forcément que l'API de gestion HTTP soit déjà disponible — on attend donc
# explicitement ici.
until curl -sf -u "$RABBITMQ_USER:$RABBITMQ_PASSWORD" "http://rabbitmq:15672/api/overview" > /dev/null; do
  echo "En attente de l'API de gestion RabbitMQ..."
  sleep 2
done

curl -sf -u "$RABBITMQ_USER:$RABBITMQ_PASSWORD" -X PUT "http://rabbitmq:15672/api/vhosts/plane"

curl -sf -u "$RABBITMQ_USER:$RABBITMQ_PASSWORD" -X PUT "http://rabbitmq:15672/api/users/plane" \
  -H "content-type: application/json" \
  -d "{\"password\":\"${PLANE_RABBITMQ_PASSWORD}\",\"tags\":\"\"}"

curl -sf -u "$RABBITMQ_USER:$RABBITMQ_PASSWORD" -X PUT "http://rabbitmq:15672/api/permissions/plane/plane" \
  -H "content-type: application/json" \
  -d '{"configure":".*","write":".*","read":".*"}'

echo "RabbitMQ provisionné pour Plane (vhost=plane, user=plane)."
