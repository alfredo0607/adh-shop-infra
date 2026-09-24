#!/usr/bin/env bash
# Exercises the operational scripts against real fixtures.
#
# ShellCheck reads syntax, not behaviour. Splitting an nginx directive on ":"
# is valid shell that returns "3000;" instead of "3000", and only a deployment
# reveals it. Both scripting bugs found so far had that shape.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT/terraform/scripts/container-api-ec2"
DEPLOY="$SCRIPT_DIR/deploy.sh"

failures=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf '  ok    %-44s -> %s\n' "$label" "${actual:-<empty>}"
  else
    printf '  FAIL  %-44s -> got %s, want %s\n' "$label" "${actual:-<empty>}" "${expected:-<empty>}" >&2
    failures=$(( failures + 1 ))
  fi
}

fail() {
  printf '  FAIL  %s\n' "$*" >&2
  failures=$(( failures + 1 ))
}

# ── Port extraction ───────────────────────────────────────────────────────────
#
# Runs the expression deploy.sh actually contains, rather than a copy of it.
#
# The first version of this test restated the sed command. That copy was correct
# while the script's own line had a control byte where the backreference
# belonged, so the test passed against a script that returned an empty port. A
# test that restates the logic only ever verifies the restatement.

SED_EXPR=$(sed -n "s/^BLUE_PORT=.*sed -n '\(.*\)' \"\$UPSTREAM_CONF\".*/\1/p" "$DEPLOY")

echo "Port extraction"

if [[ -z "$SED_EXPR" ]]; then
  fail "could not find the extraction expression in deploy.sh"
else
  printf '  ok    %-44s %s\n' "read from deploy.sh" "$SED_EXPR"

  extract_port() { sed -n "$SED_EXPR" | head -1; }

  check "standard directive" 3000 "$(printf 'upstream a {\n    server 127.0.0.1:3000;\n}\n' | extract_port)"
  check "extra whitespace" 3001 "$(printf '  server   127.0.0.1:3001 ;\n' | extract_port)"
  check "no indentation" 8080 "$(printf 'server 127.0.0.1:8080;\n' | extract_port)"
  check "ignores other hosts" 3000 "$(printf 'server 10.0.0.5:9999;\nserver 127.0.0.1:3000;\n' | extract_port)"
  check "no match is empty" "" "$(printf 'upstream a {\n}\n' | extract_port)"
fi

# ── Blue/green pairing ────────────────────────────────────────────────────────

echo "Blue/green pairing"
pair() { if (( $1 % 2 == 0 )); then echo $(( $1 + 1 )); else echo $(( $1 - 1 )); fi; }

check "even flips up" 3001 "$(pair 3000)"
check "odd flips down" 3000 "$(pair 3001)"
check "returns to itself" 3000 "$(pair "$(pair 3000)")"

# ── File health ───────────────────────────────────────────────────────────────

echo "File health"

for script in "$SCRIPT_DIR"/*.sh; do
  name=$(basename "$script")

  if bash -n "$script" 2>/dev/null; then
    printf '  ok    %-44s parses\n' "$name"
  else
    fail "$name does not parse"
  fi

  # A control character is how the backreference was lost: an escape written in
  # the wrong kind of string became byte 0x01, invisible in an editor and in the
  # diff, and the script silently substituted nothing.
  if LC_ALL=C grep -qP '[\x00-\x08\x0b\x0c\x0e-\x1f]' "$script" 2>/dev/null; then
    fail "$name contains a control character"
  else
    printf '  ok    %-44s is plain text\n' "$name"
  fi

  # A carriage return in the shebang makes the host report a missing interpreter
  # whose name nobody can see.
  if LC_ALL=C grep -q $'\r' "$script"; then
    fail "$name has CRLF line endings"
  else
    printf '  ok    %-44s uses LF endings\n' "$name"
  fi
done

if (( failures == 0 )); then
  echo "All checks passed."
else
  echo "$failures check(s) failed" >&2
  exit 1
fi
