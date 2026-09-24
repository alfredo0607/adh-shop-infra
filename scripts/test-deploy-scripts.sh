#!/usr/bin/env bash
# Exercises the parsing inside the operational scripts against real fixtures.
#
# ShellCheck cannot catch this class of bug: splitting an nginx directive on
# ":" is valid shell that returns "3000;" instead of "3000", and the failure
# only appears when a deployment runs. Both bugs found so far in these scripts
# were of exactly this shape.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY="$ROOT/terraform/scripts/container-api-ec2/deploy.sh"

failures=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf '  ok    %-44s -> %s\n' "$label" "$actual"
  else
    printf '  FAIL  %-44s -> got %s, want %s\n' "$label" "${actual:-empty}" "$expected" >&2
    failures=$(( failures + 1 ))
  fi
}

# The expression deploy.sh uses to read the active port, kept in step with it.
extract_port() {
  sed -n 's/.*server[[:space:]]\{1,\}127\.0\.0\.1:\([0-9]\{1,\}\).*/\1/p' | head -1
}

echo "Port extraction"
check "standard directive"  3000 "$(printf 'upstream a {\n    server 127.0.0.1:3000;\n}\n' | extract_port)"
check "extra whitespace"    3001 "$(printf '  server   127.0.0.1:3001 ;\n'              | extract_port)"
check "no indentation"      8080 "$(printf 'server 127.0.0.1:8080;\n'                   | extract_port)"
check "ignores other hosts" 3000 "$(printf 'server 10.0.0.5:9999;\nserver 127.0.0.1:3000;\n' | extract_port)"
check "no match is empty"   ""   "$(printf 'upstream a {\n}\n'                          | extract_port)"

echo "Blue/green pairing"
pair() { if (( $1 % 2 == 0 )); then echo $(( $1 + 1 )); else echo $(( $1 - 1 )); fi; }
check "even flips up"   3001 "$(pair 3000)"
check "odd flips down"  3000 "$(pair 3001)"
check "stays in pair"   3000 "$(pair "$(pair 3000)")"

echo "Script health"
for script in "$ROOT"/terraform/scripts/container-api-ec2/*.sh; do
  if bash -n "$script" 2>/dev/null; then
    printf '  ok    %-44s parses\n' "$(basename "$script")"
  else
    printf '  FAIL  %-44s does not parse\n' "$(basename "$script")" >&2
    failures=$(( failures + 1 ))
  fi
done

# The expression under test must still be the one the script uses.
if grep -q 'server\[\[:space:\]\]' "$DEPLOY"; then
  printf '  ok    %-44s matches the script\n' "extraction expression"
else
  printf '  FAIL  %-44s drifted from the script\n' "extraction expression" >&2
  failures=$(( failures + 1 ))
fi

(( failures == 0 )) || { echo "$failures check(s) failed" >&2; exit 1; }
echo "All checks passed."
