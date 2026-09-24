#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  deploy.sh — Blue/green deployment of a container behind nginx.
#
#  Usage: ./deploy.sh <image> <app-name>
#    image     Fully qualified ECR image, tagged with the commit SHA
#    app-name  Must match the name given to add-api.sh
#
#  The old container keeps serving until the new one answers its health check.
#  If the new image is broken, the deployment aborts and nothing changed.
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

IMAGE="${1:?usage: deploy.sh <image> <app-name>}"
APP="${2:?usage: deploy.sh <image> <app-name>}"

PROJECT="${PROJECT:-adh-shop}"
REGION="${AWS_REGION:-us-east-1}"
PARAMETER_PATH="${PARAMETER_PATH:-/$PROJECT}"

UPSTREAM_CONF="/etc/nginx/conf.d/upstreams/$APP.conf"
CONTAINER_PORT=3000
HEALTH_PATH="${HEALTH_PATH:-/health}"
HEALTH_RETRIES=30
HEALTH_INTERVAL=2

log() { printf '[deploy] %s\n' "$*"; }
fail() { printf '[deploy] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$UPSTREAM_CONF" ]] || fail "unknown app '$APP' — run add-api.sh first"

# ── Colour selection ──────────────────────────────────────────────────────────
# Two fixed host ports per app. Whichever one nginx is not currently pointing at
# is where the new version starts.

# Captures the digits explicitly. Splitting the line on ":" instead returns
# "3000;" — nginx directives end in a semicolon — and every later arithmetic
# test then fails with a syntax error rather than a wrong number.
BLUE_PORT=$(sed -n 's/.*server[[:space:]]\{1,\}127\.0\.0\.1:\([0-9]\{1,\}\).*/\1/p' "$UPSTREAM_CONF" | head -1)

[[ "$BLUE_PORT" =~ ^[0-9]+$ ]] || fail "could not read a port from $UPSTREAM_CONF (got '${BLUE_PORT:-empty}')"

# Ports are allocated in even/odd pairs by add-api.sh: the even one is blue,
# the odd one green. Parity alone decides, with no string parsing to get wrong.
if (( BLUE_PORT % 2 == 0 )); then
  GREEN_PORT=$(( BLUE_PORT + 1 ))
else
  GREEN_PORT=$(( BLUE_PORT - 1 ))
fi

ACTIVE_CONTAINER="$APP-$BLUE_PORT"
NEW_CONTAINER="$APP-$GREEN_PORT"

log "active: $ACTIVE_CONTAINER on :$BLUE_PORT"
log "deploying $IMAGE as $NEW_CONTAINER on :$GREEN_PORT"

# ── Authenticate with ECR ─────────────────────────────────────────────────────
# Done on every deployment, not only at boot. The token from `get-login-password`
# expires after twelve hours, so a host that has been up longer than that would
# otherwise fail the pull with "no basic auth credentials".
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com" >/dev/null
log "authenticated with ECR"

docker pull "$IMAGE"

# ── Materialise configuration from Parameter Store ────────────────────────────
# Written with a restrictive umask and removed by the trap, so the secrets exist
# on disk only for the seconds docker needs to read them.
ENV_FILE=$(umask 077 && mktemp "/tmp/$APP.env.XXXXXX")
cleanup() {
  rm -f "$ENV_FILE"
  # Leave no half-started container behind if the script died mid-flight.
  if [[ "${DEPLOY_OK:-0}" -ne 1 ]]; then
    docker rm -f "$NEW_CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log "reading configuration from SSM $PARAMETER_PATH"

# Built through python rather than by splitting the CLI's text output.
#
# A PEM key is multi-line, and an env file has no syntax for that: every line
# after the first is read as its own variable, which docker rejects with a
# complaint naming "-----END PRIVATE KEY-----". Tab-delimited output has the
# same problem from the other side, since the value itself contains newlines.
#
# Multi-line values are therefore base64-encoded and published as <NAME>_BASE64.
# The encoding is visible in the name, so an application reading it knows to
# decode rather than discovering a mangled key at runtime.
aws ssm get-parameters-by-path \
  --path "$PARAMETER_PATH" \
  --recursive \
  --with-decryption \
  --region "$REGION" \
  --output json \
  | python3 -c '
import base64, json, sys

parameters = json.load(sys.stdin).get("Parameters", [])
lines = []

for parameter in parameters:
    name = parameter["Name"].rsplit("/", 1)[-1]
    value = parameter["Value"]

    if "\n" in value or "\r" in value:
        encoded = base64.b64encode(value.encode()).decode()
        lines.append(f"{name}_BASE64={encoded}")
    else:
        lines.append(f"{name}={value}")

sys.stdout.write("\n".join(sorted(lines)) + "\n")
' > "$ENV_FILE"

[[ -s "$ENV_FILE" ]] || fail "no parameters found under $PARAMETER_PATH"
log "loaded $(wc -l < "$ENV_FILE") parameters"

# ── Start the new colour ──────────────────────────────────────────────────────
docker rm -f "$NEW_CONTAINER" >/dev/null 2>&1 || true

# Published on the loopback interface only. The security group does not open
# these ports, and binding to 127.0.0.1 means that even if it did, the container
# would still be reachable exclusively through nginx — and therefore only over
# TLS, with the proxy headers the application expects.
docker run -d \
  --name "$NEW_CONTAINER" \
  --restart unless-stopped \
  --env-file "$ENV_FILE" \
  -e "PORT=$CONTAINER_PORT" \
  -p "127.0.0.1:$GREEN_PORT:$CONTAINER_PORT" \
  "$IMAGE" >/dev/null

# ── Health check ──────────────────────────────────────────────────────────────
log "waiting for $NEW_CONTAINER to become healthy"

healthy=0
for attempt in $(seq 1 "$HEALTH_RETRIES"); do
  if ! docker ps --format '{{.Names}}' | grep -qx "$NEW_CONTAINER"; then
    log "container exited during startup. Last lines:"
    docker logs --tail 40 "$NEW_CONTAINER" || true
    fail "new version failed to start — $ACTIVE_CONTAINER is untouched"
  fi

  if curl -fsS --max-time 3 "http://127.0.0.1:$GREEN_PORT$HEALTH_PATH" >/dev/null 2>&1; then
    healthy=1
    log "healthy after ${attempt} attempt(s)"
    break
  fi

  sleep "$HEALTH_INTERVAL"
done

if [[ "$healthy" -ne 1 ]]; then
  log "never became healthy. Last lines:"
  docker logs --tail 40 "$NEW_CONTAINER" || true
  fail "health check failed — $ACTIVE_CONTAINER is untouched and still serving"
fi

# ── Switch traffic ────────────────────────────────────────────────────────────
#
# Rewriting only the upstream file leaves the certbot-managed virtual host
# alone. `nginx -t` runs before the reload so a malformed file can never take
# the proxy down, and the reload drains existing connections rather than cutting
# them.
#
# Written with sudo tee: the script runs as ec2-user and everything under
# /etc/nginx belongs to root. A redirect is evaluated by the calling shell
# before sudo would ever run, so `sudo cat > file` fails exactly as an
# unprivileged redirect does.
write_upstream() {
  sudo tee "$UPSTREAM_CONF" > /dev/null <<UPSTREAM
upstream $APP {
    server 127.0.0.1:$1;
}
UPSTREAM
}

write_upstream "$GREEN_PORT"

if ! sudo nginx -t 2>/dev/null; then
  write_upstream "$BLUE_PORT"
  fail "nginx rejected the new upstream — reverted, $ACTIVE_CONTAINER still serving"
fi

sudo systemctl reload nginx
log "traffic switched to :$GREEN_PORT"

DEPLOY_OK=1

# ── Retire the old colour ─────────────────────────────────────────────────────
# Only now, once traffic is already elsewhere. The original ordering stopped the
# old container first, which guaranteed a gap and left nothing to fall back to
# when the new image turned out to be broken.
if docker ps -a --format '{{.Names}}' | grep -qx "$ACTIVE_CONTAINER"; then
  docker stop "$ACTIVE_CONTAINER" >/dev/null || true
  docker rm "$ACTIVE_CONTAINER" >/dev/null || true
  log "retired $ACTIVE_CONTAINER"
fi

docker image prune -f >/dev/null

log "done: $APP is serving $IMAGE on :$GREEN_PORT"
