#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  add-keys.sh — Publish key material and configuration to Parameter Store.
#
#  Usage:
#    ./add-keys.sh                 keys from S3 only
#    ./add-keys.sh <env-file>      keys from S3, plus KEY=value lines from a file
#
#  Key material is never kept on this host. Each key is pulled from the scripts
#  bucket into a temporary directory, written to Parameter Store as a
#  SecureString, and the directory is removed by a trap that fires whether the
#  script succeeds, fails or is interrupted. The window in which a private key
#  exists on disk is the few seconds between those two steps.
#
#  The applications read what they need from Parameter Store through the
#  instance role, so nothing has to be copied into a container or an env file
#  that outlives the deployment.
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

PROJECT="${PROJECT:-adh-shop}"
REGION="${AWS_REGION:-us-east-1}"
PARAMETER_PATH="${PARAMETER_PATH:-/$PROJECT}"
S3_BUCKET="${S3_BUCKET:-}"

ENV_FILE="${1:-}"

command -v aws >/dev/null || { echo "[add-keys] ERROR: AWS CLI not installed" >&2; exit 1; }

# Discover the bucket rather than requiring it. The host already knows which
# account it is in, and the name follows from the project.
if [[ -z "$S3_BUCKET" ]]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  S3_BUCKET="${PROJECT}-scripts-${ACCOUNT_ID}"
fi

echo "[add-keys] bucket: s3://$S3_BUCKET"
echo "[add-keys] parameters: $PARAMETER_PATH"

# ── Temporary directory, removed on any exit ──────────────────────────────────
TMP_KEYS=$(mktemp -d)
chmod 700 "$TMP_KEYS"
cleanup() {
  # shred where available: on a journalling filesystem an unlink alone leaves
  # the blocks readable until they are reused.
  find "$TMP_KEYS" -type f -exec shred -u {} \; 2>/dev/null || true
  rm -rf "$TMP_KEYS"
}
trap cleanup EXIT INT TERM

published=0

# ── CloudFront URL signing key ────────────────────────────────────────────────
#
# The API signs image URLs with this. CloudFront verifies them against the
# public half, which Terraform registered as a key group when the distribution
# was created.
CF_KEY="keys/cloudfront/private.pem"

if aws s3api head-object --bucket "$S3_BUCKET" --key "$CF_KEY" >/dev/null 2>&1; then
  echo "[add-keys] fetching the CloudFront signing key"
  aws s3 cp "s3://$S3_BUCKET/$CF_KEY" "$TMP_KEYS/cloudfront-private.pem" --quiet

  aws ssm put-parameter \
    --region "$REGION" \
    --name "$PARAMETER_PATH/CDN_PRIVATE_KEY" \
    --value "file://$TMP_KEYS/cloudfront-private.pem" \
    --type SecureString \
    --overwrite \
    --no-cli-pager > /dev/null

  echo "[add-keys] CDN_PRIVATE_KEY published"
  published=$(( published + 1 ))
else
  echo "[add-keys] no key at s3://$S3_BUCKET/$CF_KEY — skipping"
  echo "[add-keys]   openssl genrsa -out private.pem 2048"
  echo "[add-keys]   aws s3 cp private.pem s3://$S3_BUCKET/$CF_KEY && rm private.pem"
fi

# ── Application configuration ─────────────────────────────────────────────────
#
# Optional. Values the infrastructure already knows are published by Terraform;
# this covers the ones it must not hold, such as the payment gateway
# credentials.
SECRET_PATTERN='(KEY|SECRET|TOKEN|PASSWORD|PRIVATE)'

if [[ -n "$ENV_FILE" ]]; then
  [[ -f "$ENV_FILE" ]] || { echo "[add-keys] ERROR: $ENV_FILE not found" >&2; exit 1; }

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line// }" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *=* ]] && continue

    name="${line%%=*}"
    value="${line#*=}"
    name="${name// }"
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"

    if [[ "$name" =~ $SECRET_PATTERN ]]; then type="SecureString"; else type="String"; fi

    aws ssm put-parameter \
      --region "$REGION" \
      --name "$PARAMETER_PATH/$name" \
      --value "$value" \
      --type "$type" \
      --overwrite \
      --no-cli-pager > /dev/null

    # The value is never echoed: this output routinely ends up in a CI log.
    printf '[add-keys] %-28s %s\n' "$name" "$type"
    published=$(( published + 1 ))
  done < "$ENV_FILE"
fi

echo "[add-keys] published $published parameters"

count=$(aws ssm get-parameters-by-path \
  --path "$PARAMETER_PATH" \
  --recursive \
  --region "$REGION" \
  --query 'length(Parameters)' \
  --output text)

echo "[add-keys] $count parameters now readable under $PARAMETER_PATH"
echo "[add-keys] local copies removed"
