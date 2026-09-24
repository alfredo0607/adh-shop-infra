#!/usr/bin/env bash
# Verifies that every output a stack reads through terraform_remote_state is
# actually declared by the stack that owns it.
#
# terraform validate does not catch this: remote state outputs resolve at apply
# time, so a missing one surfaces only once infrastructure is already changing.
# This moves that failure into the pull request.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACKS="$ROOT/terraform/infrastructures"

# Collected rather than counted inside a pipeline: a variable assigned in a
# subshell does not survive it, which would silently turn failures into passes.
problems=()

for stack_dir in "$STACKS"/*/; do
  stack="$(basename "$stack_dir")"
  compgen -G "$stack_dir"'*.tf' > /dev/null || continue

  # Map each remote-state alias to the stack it reads, via its state key.
  declare -A owner_of=()
  while read -r alias key; do
    [[ -n "$alias" ]] && owner_of["$alias"]="${key%%/*}"
  done < <(awk '
    /data +"terraform_remote_state"/ { alias=$3; gsub(/"/, "", alias) }
    /key *=/ && alias != "" { k=$3; gsub(/"/, "", k); print alias, k; alias="" }
  ' "$stack_dir"*.tf)

  for alias in "${!owner_of[@]}"; do
    owner="${owner_of[$alias]}"
    owner_outputs="$STACKS/$owner/outputs.tf"

    if [[ ! -f "$owner_outputs" ]]; then
      problems+=("$stack reads the state of '$owner', which declares no outputs")
      continue
    fi

    while read -r output; do
      [[ -n "$output" ]] || continue
      if ! grep -qE "^output +\"$output\"" "$owner_outputs"; then
        problems+=("$stack reads '$output' from '$owner', which does not declare it")
      fi
    done < <(
      grep -ohE "data\.terraform_remote_state\.$alias\.outputs\.[a-zA-Z0-9_]+" "$stack_dir"*.tf 2>/dev/null \
        | sed 's/.*outputs\.//' | sort -u
    )
  done

  unset owner_of
done

if (( ${#problems[@]} > 0 )); then
  echo "Cross-stack output check failed:" >&2
  printf '  - %s\n' "${problems[@]}" >&2
  exit 1
fi

echo "All cross-stack outputs resolve."
