#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
#  add-keys.sh — Publish application configuration to SSM Parameter Store.
#
#  Usage: ./add-keys.sh <env-file>
#
#  Reads KEY=value lines and writes each one as a parameter under
#  $PARAMETER_PATH. Anything whose name matches the secret pattern is stored as
#  a SecureString; the rest as String, so a plain table name is readable in the
#  console without decryption.
#
#  Run from an operator's machine. The source file is never committed and never
#  uploaded anywhere: Parameter Store is the source of truth.
#
#  The previous design kept .pem files and .env files in an S3 bucket and copied
#  them onto the host at boot. That made a bucket policy the only thing standing
#  between a signing key and the internet, and left the values on disk. Here the
#  secrets go straight to Parameter Store, and deploy.sh materialises them for
#  the few seconds docker needs to read them.
# ════════════════════════════════════════════════════════════════════════════
set -euo pipefail

ENV_FILE="${1:?usage: add-keys.sh <env-file>}"
PROJECT="${PROJECT:-adh-shop}"
REGION="${AWS_REGION:-us-east-1}"
PARAMETER_PATH="${PARAMETER_PATH:-/$PROJECT}"

[[ -f "$ENV_FILE" ]] || { echo "[add-keys] ERROR: $ENV_FILE not found" >&2; exit 1; }
command -v aws >/dev/null || { echo "[add-keys] ERROR: AWS CLI not installed" >&2; exit 1; }

# Names matching this are stored encrypted.
SECRET_PATTERN='(KEY|SECRET|TOKEN|PASSWORD|PRIVATE)'

published=0
while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip blanks and comments
  [[ -z "${line// }" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" != *=* ]] && continue

  name="${line%%=*}"
  value="${line#*=}"
  name="${name// }"

  # Strip surrounding quotes if the file used them
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"

  if [[ "$name" =~ $SECRET_PATTERN ]]; then
    type="SecureString"
  else
    type="String"
  fi

  aws ssm put-parameter \
    --region "$REGION" \
    --name "$PARAMETER_PATH/$name" \
    --value "$value" \
    --type "$type" \
    --overwrite \
    --no-cli-pager > /dev/null

  # The value itself is never echoed: this output routinely ends up in a CI log.
  printf '[add-keys] %-28s %s\n' "$name" "$type"
  published=$(( published + 1 ))
done < "$ENV_FILE"

echo "[add-keys] published $published parameters under $PARAMETER_PATH"

echo "[add-keys] verifying..."
count=$(aws ssm get-parameters-by-path \
  --path "$PARAMETER_PATH" \
  --recursive \
  --region "$REGION" \
  --query 'length(Parameters)' \
  --output text)

echo "[add-keys] $count parameters readable under $PARAMETER_PATH"
