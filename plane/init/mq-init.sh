#!/bin/sh
set -eu

# rabbitmqadmin (CLI bundlé dans l'image rabbitmq-management, parle à l'API
# de gestion HTTP en interne) sert aussi de sonde d'attente : le healthcheck
# du service rabbitmq garantit que l'AMQP répond, pas forcément que l'API de
# gestion HTTP soit déjà disponible.
until rabbitmqadmin --host=rabbitmq --username="$RABBITMQ_USER" --password="$RABBITMQ_PASSWORD" \
  list vhosts > /dev/null 2>&1; do
  echo "En attente de l'API de gestion RabbitMQ..."
  sleep 2
done

rabbitmqadmin --host=rabbitmq --username="$RABBITMQ_USER" --password="$RABBITMQ_PASSWORD" \
  declare vhost "name=plane"

rabbitmqadmin --host=rabbitmq --username="$RABBITMQ_USER" --password="$RABBITMQ_PASSWORD" \
  declare user "name=plane" "password=${PLANE_RABBITMQ_PASSWORD}" "tags="

rabbitmqadmin --host=rabbitmq --username="$RABBITMQ_USER" --password="$RABBITMQ_PASSWORD" \
  declare permission "vhost=plane" "user=plane" "configure=.*" "write=.*" "read=.*"

echo "RabbitMQ provisionné pour Plane (vhost=plane, user=plane)."
