#!/bin/sh
set -eu

mc alias set localminio http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

until mc admin info localminio > /dev/null 2>&1; do
  echo "En attente de Minio..."
  sleep 2
done

mc mb --ignore-existing localminio/plane

cat > /tmp/plane-policy.json << JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:*"],
    "Resource": ["arn:aws:s3:::plane", "arn:aws:s3:::plane/*"]
  }]
}
JSON

mc admin user add localminio plane "$PLANE_MINIO_PASSWORD"
mc admin policy create localminio plane-policy /tmp/plane-policy.json
mc admin policy attach localminio plane-policy --user plane

echo "Minio provisionné pour Plane (bucket=plane, user=plane)."
