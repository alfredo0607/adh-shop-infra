#!/usr/bin/env bash
# terraform init for a stack, with the state bucket derived from the account.
#
# The backend block cannot use variables: Terraform resolves it before the
# variable system exists, so `bucket = var.something` is invalid by design. The
# usual workaround is a backend.hcl file, which means an account id either gets
# committed to a public repository or retyped by hand.
#
# Deriving it here removes both. The name comes from bootstrap/remote-state,
# and the account from whoever is currently authenticated — so the state a
# stack writes to always belongs to the account it is deploying into.
#
#   ./scripts/tf-init.sh terraform/infrastructures/network
set -euo pipefail

STACK="${1:?usage: tf-init.sh <stack-directory> [extra terraform init args]}"
shift

PROJECT="${PROJECT:-adh-shop}"
REGION="${AWS_REGION:-us-east-1}"

command -v aws >/dev/null || { echo "AWS CLI not installed" >&2; exit 1; }
[[ -d "$STACK" ]] || { echo "No such stack: $STACK" >&2; exit 1; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${PROJECT}-terraform-state-${ACCOUNT}"

echo "Stack:   $STACK"
echo "Backend: s3://$BUCKET ($REGION), account $ACCOUNT"

terraform -chdir="$STACK" init \
  -backend-config="bucket=$BUCKET" \
  -backend-config="region=$REGION" \
  "$@"
