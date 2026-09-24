#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
#  bootstrap.sh — User data for the container host.
#
#  Runs once, as root, at first boot. It prepares the machine and deploys
#  nothing: the first deployment is the pipeline's job.
#
#    1. Docker and nginx
#    2. CloudWatch agent, so the logs outlive the instance
#    3. Management scripts pulled from S3
#    4. Log in to ECR
#
#  Interpolated by Terraform via templatefile(): ${project}, ${region},
#  ${scripts_bucket}, ${parameter_path}.
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

PROJECT="${project}"
REGION="${region}"
S3_BUCKET="${scripts_bucket}"
PARAMETER_PATH="${parameter_path}"

# A single fixed location. The original design keyed this directory on the
# environment name, which meant every consumer had to agree on the same
# spelling of it, and a mismatch silently produced a container with no
# configuration. One environment, one path, nothing to keep in sync.
APP_HOME="/opt/$${PROJECT}"

LOG="/var/log/bootstrap.log"
exec > >(tee -a "$LOG") 2>&1

echo "════════════════════════════════════════"
echo "[bootstrap] start: $(date --iso-8601=seconds)"
echo "════════════════════════════════════════"

# ── 1. System ─────────────────────────────────────────────────────────────────
dnf update -y

# ── 2. Docker ─────────────────────────────────────────────────────────────────
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

# Cap the log a container can write. Without this a chatty or looping
# application fills the root volume and takes the host down with it.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DOCKER_DAEMON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
DOCKER_DAEMON
systemctl restart docker

# ── 3. nginx and certbot ──────────────────────────────────────────────────────
dnf install -y nginx python3-certbot-nginx

cat > /etc/nginx/nginx.conf <<'NGINX_MAIN'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" rt=$request_time';

    access_log /var/log/nginx/access.log main;

    sendfile           on;
    tcp_nopush         on;
    keepalive_timeout  65;
    types_hash_max_size           4096;
    server_names_hash_bucket_size 128;

    # The version number tells an attacker which CVEs to try first.
    server_tokens off;

    client_max_body_size 2m;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Upstreams are separate files so a deployment can repoint one atomically
    # without rewriting the virtual host that certbot manages.
    include /etc/nginx/conf.d/upstreams/*.conf;
    include /etc/nginx/conf.d/*.conf;
}
NGINX_MAIN

mkdir -p /etc/nginx/conf.d/upstreams
nginx -t
systemctl enable --now nginx

# certbot installs a renewal timer, but it is not enabled by default on this
# AMI. Without it the certificate silently expires after ninety days.
systemctl enable --now certbot-renew.timer 2>/dev/null || true

# ── 4. CloudWatch agent ───────────────────────────────────────────────────────
# An instance is replaceable; its logs should not die with it.
dnf install -y amazon-cloudwatch-agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CW_AGENT
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/$${PROJECT}-container-host/nginx/access",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/$${PROJECT}-container-host/nginx/error",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/bootstrap.log",
            "log_group_name": "/$${PROJECT}-container-host/bootstrap",
            "retention_in_days": 30
          }
        ]
      }
    }
  }
}
CW_AGENT
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true

# ── 5. Management scripts ─────────────────────────────────────────────────────
echo "[bootstrap] fetching management scripts from s3://$S3_BUCKET/scripts/"
mkdir -p "$APP_HOME"
aws s3 sync "s3://$S3_BUCKET/scripts/" "$APP_HOME/" --exclude "*" --include "*.sh"
chmod +x "$APP_HOME"/*.sh
chown -R ec2-user:ec2-user "$APP_HOME"

# Configuration is NOT fetched here.
#
# The original design copied .env files and private keys out of S3 at boot.
# That makes a bucket the source of truth for signing keys: one wrong bucket
# policy and they are public, and the values sit on disk in between. Here the
# source of truth is Parameter Store, the instance role is scoped to
# "$PARAMETER_PATH/*", and deploy.sh materialises the values at deploy time
# into a file it deletes immediately afterwards.
echo "[bootstrap] configuration source: SSM Parameter Store $PARAMETER_PATH"

# ── 6. ECR login ──────────────────────────────────────────────────────────────
# Also performed by deploy.sh on every run. The token issued here expires after
# twelve hours, so this login only covers a deployment that happens shortly
# after boot; it is kept so the host is usable immediately.
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "[bootstrap] complete: $(date --iso-8601=seconds)"
echo "[bootstrap] next: point DNS at this host, then run $APP_HOME/add-api.sh"
