#!/bin/sh
set -eu

until redis-cli -h redis -a "$REDIS_PASSWORD" --no-auth-warning ping > /dev/null 2>&1; do
  echo "En attente de Redis..."
  sleep 2
done

# Idempotent : (re)définit le user à chaque exécution — resynchronise le mot
# de passe si APANEL_REDIS_PASSWORD change. Isolation par préfixe de clés
# (~apanel:*) plutôt que par index logique : l'app doit configurer son
# client Redis/BullMQ avec ce préfixe (ex: BullMQ "prefix: apanel").
redis-cli -h redis -a "$REDIS_PASSWORD" --no-auth-warning \
  ACL SETUSER apanel on ">${APANEL_REDIS_PASSWORD}" "~apanel:*" "&*" +@all -@dangerous

# Persisté dans /data/users.acl (aclfile, cf. redis/docker-compose.yml) pour
# survivre à un redémarrage du conteneur entre deux déploiements.
redis-cli -h redis -a "$REDIS_PASSWORD" --no-auth-warning ACL SAVE

echo "Redis provisionné pour apanel (user ACL=apanel, préfixe de clés=apanel:*)."
