#!/bin/bash
set -euo pipefail

DOMAIN=${1:-jarvis.yourdomain.com}
EMAIL=${2:-admin@$DOMAIN}

echo "Setting up SSL for $DOMAIN..."

docker run --rm -p 80:80 -p 443:443 \
  -v "$(pwd)/certbot/etc:/etc/letsencrypt" \
  -v "$(pwd)/certbot/var:/var/www/certbot" \
  certbot/certbot certonly --standalone \
  -d "$DOMAIN" \
  --non-interactive --agree-tos \
  -m "$EMAIL"

echo "SSL certs generated for $DOMAIN"

docker run --rm \
  -v "$(pwd)/certbot/etc:/etc/letsencrypt" \
  alpine sh -c "
    apk add --no-cache openssl
    mkdir -p /etc/ssl/private
    openssl dhparam -out /etc/ssl/private/dhparam.pem 2048
  "

echo "Done. Set your DOMAIN in docker-compose and nginx, then start."
