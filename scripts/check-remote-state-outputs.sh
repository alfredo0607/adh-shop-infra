#!/usr/bin/env bash
# Verifies that every output a stack reads through terraform_remote_state is
# actually declared by the stack that owns it.
#
# terraform validate does not catch this: remote state outputs are resolved at
# apply time, so a missing one surfaces only once you are already changing
# infrastructure. This check moves that failure to the pull request.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACKS="$ROOT/terraform/infrastructures"
failed=0

for stack in "$STACKS"/*/; do
  name="$(basename "$stack")"
  [[ -f "$stack/main.tf" ]] || continue

  # Each `data "terraform_remote_state" "<alias>"` block records which stack it
  # points at through its key.
  while read -r alias key; do
    owner="${key%%/*}"
    owner_outputs="$STACKS/$owner/outputs.tf"

    if [[ ! -f "$owner_outputs" ]]; then
      echo "  $name reads state of '$owner', which declares no outputs"
      failed=1
      continue
    fi

    # Outputs consumed from this particular alias.
    grep -oE "data\.terraform_remote_state\.$alias\.outputs\.[a-z_]+" "$stack"/*.tf 2>/dev/null \
      | sed 's/.*outputs\.//' | sort -u \
      | while read -r output; do
          if ! grep -qE "^output \"$output\"" "$owner_outputs"; then
            echo "  MISSING: $name reads '$output' from '$owner', which does not declare it"
            exit 1
          fi
        done || failed=1
  done < <(awk '
    /data "terraform_remote_state"/ { alias=$3; gsub(/"/,"",alias) }
    /key *=/ && alias != "" { k=$3; gsub(/"/,"",k); print alias, k; alias="" }
  ' "$stack"/*.tf)
done

if [[ "$failed" -eq 0 ]]; then
  echo "All cross-stack outputs resolve."
else
  echo "Cross-stack output check failed." >&2
fi

exit "$failed"
