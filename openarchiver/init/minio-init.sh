#!/bin/sh
set -eu

mc alias set localminio http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

until mc admin info localminio > /dev/null 2>&1; do
  echo "En attente de Minio..."
  sleep 2
done

mc mb --ignore-existing localminio/openarchiver

cat > /tmp/openarchiver-policy.json << JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:*"],
    "Resource": ["arn:aws:s3:::openarchiver", "arn:aws:s3:::openarchiver/*"]
  }]
}
JSON

mc admin user add localminio openarchiver "$OPENARCHIVER_MINIO_PASSWORD"
mc admin policy create localminio openarchiver-policy /tmp/openarchiver-policy.json
mc admin policy attach localminio openarchiver-policy --user openarchiver

echo "Minio provisionné pour OpenArchiver (bucket=openarchiver, user=openarchiver)."
