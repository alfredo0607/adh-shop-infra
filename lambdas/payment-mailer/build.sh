#!/usr/bin/env bash
# Prepares build/, the directory Terraform zips into the Lambda: the source and
# the production dependencies only.
#
# The AWS SDK is left out on purpose. The Node.js runtime already ships it, and
# it is a development dependency here only so the tests can import it.
#
#   ./lambdas/payment-mailer/build.sh     (run before plan and apply)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$DIR/build"

rm -rf "$BUILD"
mkdir -p "$BUILD"
cp -R "$DIR/src" "$DIR/package.json" "$DIR/package-lock.json" "$BUILD/"

(cd "$BUILD" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund)

echo "Built $BUILD"
