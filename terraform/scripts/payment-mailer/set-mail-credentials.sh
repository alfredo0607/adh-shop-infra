#!/usr/bin/env bash
# Publishes the Gmail account the payment emails are sent from.
#
# The password is a Gmail *app password* (Google Account → Security → 2-Step
# Verification → App passwords), never the account's own. It is read from the
# terminal without echo, so it lands in neither the shell history nor Terraform
# state, and is stored as a SecureString the Lambda alone may decrypt.
#
#   ./terraform/scripts/payment-mailer/set-mail-credentials.sh store@gmail.com
set -euo pipefail

USER_EMAIL="${1:?usage: set-mail-credentials.sh <gmail address>}"
PARAMETER_PATH="${PARAMETER_PATH:-/adh-shop-mailer}"

[[ "$USER_EMAIL" == *@* ]] || { echo "Not an email address: $USER_EMAIL" >&2; exit 1; }

read -r -s -p "App password for $USER_EMAIL: " PASSWORD
echo
# Google shows app passwords in groups of four; the spaces are not part of it.
PASSWORD="${PASSWORD// /}"
[[ ${#PASSWORD} -eq 16 ]] || { echo "An app password has 16 characters; got ${#PASSWORD}" >&2; exit 1; }

aws ssm put-parameter --name "$PARAMETER_PATH/MAIL_USER" --type String \
  --value "$USER_EMAIL" --overwrite >/dev/null
aws ssm put-parameter --name "$PARAMETER_PATH/MAIL_PASSWORD" --type SecureString \
  --value "$PASSWORD" --overwrite >/dev/null
unset PASSWORD

echo "Published $PARAMETER_PATH/MAIL_USER and $PARAMETER_PATH/MAIL_PASSWORD."
echo "The function reads them on its next send; nothing needs a redeploy."
