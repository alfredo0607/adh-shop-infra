#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  add-api.sh — Publish an application on a subdomain over HTTPS.
#
#  Usage: ./add-api.sh <subdomain> <base-port> [email]
#    subdomain   FQDN already pointing at this host's elastic IP
#    base-port   EVEN port. This and base-port+1 form the blue/green pair
#
#  Run once per application. Afterwards deploy.sh handles every release.
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SUBDOMAIN="${1:?usage: add-api.sh <subdomain> <base-port> [email]}"
BASE_PORT="${2:?usage: add-api.sh <subdomain> <base-port> [email]}"
EMAIL="${3:-${CERTBOT_EMAIL:-}}"

[[ -n "$EMAIL" ]] || { echo "[add-api] ERROR: an email is required for Let's Encrypt" >&2; exit 1; }

# deploy.sh flips between an even port and the odd one above it. An odd base
# would make the pair overlap with the next application's.
if (( BASE_PORT % 2 != 0 )); then
  echo "[add-api] ERROR: base-port must be even (it pairs with $((BASE_PORT + 1)))" >&2
  exit 1
fi

APP="${SUBDOMAIN%%.*}"
UPSTREAM_DIR="/etc/nginx/conf.d/upstreams"
UPSTREAM_CONF="$UPSTREAM_DIR/$APP.conf"
VHOST_CONF="/etc/nginx/conf.d/$SUBDOMAIN.conf"

sudo mkdir -p "$UPSTREAM_DIR"

# The upstream is a separate file because deploy.sh rewrites it on every
# release. The virtual host below is managed by certbot and must not be touched
# by a deployment.
if [[ ! -f "$UPSTREAM_CONF" ]]; then
  sudo tee "$UPSTREAM_CONF" > /dev/null <<UPSTREAM
upstream $APP {
    server 127.0.0.1:$BASE_PORT;
}
UPSTREAM
  echo "[add-api] upstream $APP -> 127.0.0.1:$BASE_PORT (green: $((BASE_PORT + 1)))"
fi

if [[ ! -f "$VHOST_CONF" ]]; then
  sudo tee "$VHOST_CONF" > /dev/null <<VHOST
server {
    listen 80;
    server_name $SUBDOMAIN;

    # Security headers applied at the proxy, so every application behind it is
    # covered whether or not it sets them itself.
    add_header X-Content-Type-Options    "nosniff"        always;
    add_header X-Frame-Options           "DENY"           always;
    add_header Referrer-Policy           "no-referrer"    always;
    add_header Cross-Origin-Opener-Policy "same-origin"   always;

    location / {
        proxy_pass         http://$APP;
        proxy_http_version 1.1;

        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        'upgrade';
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 90;

        # Fail fast rather than holding a client while a dead upstream times out.
        proxy_connect_timeout 5;
    }

    # Probed by the load of automated scanners that find any public host within
    # hours. Answering locally keeps that noise off the application.
    location = /nginx-health {
        access_log off;
        return 200 "ok\n";
    }
}
VHOST

  sudo nginx -t
  sudo systemctl reload nginx
  echo "[add-api] nginx serving $SUBDOMAIN -> upstream $APP"
else
  echo "[add-api] $VHOST_CONF already exists — renewing the certificate only"
fi

# certbot rewrites the virtual host above for 443 and adds the 80-to-443
# redirect. It is idempotent, so re-running is safe.
sudo certbot --nginx \
  -d "$SUBDOMAIN" \
  --non-interactive \
  --agree-tos \
  -m "$EMAIL" \
  --redirect

echo "[add-api] https://$SUBDOMAIN is live"
echo "[add-api] deploy with: ./deploy.sh <image> $APP"
