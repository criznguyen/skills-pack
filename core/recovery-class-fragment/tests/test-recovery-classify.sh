#!/usr/bin/env bash
# test-recovery-classify.sh — 5-case unit suite.
# 4 single-class cases (1 per class) + 1 multi-class suppression + 1 ambiguity.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
HOOK="$REPO_ROOT/core/recovery-class-fragment/hooks/recovery-classify.sh"
TSV="$REPO_ROOT/core/recovery-class-fragment/templates/recovery-classes.tsv"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP"
export RECOVERY_CLASS_FRAGMENT_TSV="$TSV"
export GOVERNANCE_PACK_TELEMETRY_FILE="$TMP/telemetry.jsonl"
mkdir -p "$TMP/.claude"

fail=0

run_case() {
  local name="$1" stderr="$2" expect_class="$3" expect_advisory="$4"
  local payload
  payload=$(printf '{"tool_name":"Bash","session_id":"test","tool_response":{"stderr":%s}}' \
    "$(printf '%s' "$stderr" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  local out
  out="$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null || true)"
  if [ "$expect_advisory" = "yes" ]; then
    if ! printf '%s' "$out" | grep -q "class=$expect_class"; then
      printf 'FAIL: case=%s expected class=%s in advisory; got=%s\n' "$name" "$expect_class" "$out" >&2
      fail=1
    else
      printf 'PASS: case=%s class=%s detected\n' "$name" "$expect_class"
    fi
  else
    if printf '%s' "$out" | grep -q 'RECOVERY-HINT'; then
      printf 'FAIL: case=%s expected suppression; got hint=%s\n' "$name" "$out" >&2
      fail=1
    else
      printf 'PASS: case=%s suppressed (no hint)\n' "$name"
    fi
  fi
}

run_case "transient-rate-limit"   "Error: rate limit exceeded, retry after 30s" "transient"        "yes"
run_case "config-drift-token"     "fatal: invalid token (expired)"              "config-drift"     "yes"
run_case "logic-error-typeerror"  "TypeError: cannot read property 'x' of undefined" "logic-error" "yes"
run_case "external-failure-503"   "503 Service Unavailable from upstream"       "external-failure" "yes"
run_case "multi-class-suppress"   "TypeError: rate limit hit and 503"           ""                 "no"
run_case "no-match-quiet"         "some random error message"                   ""                 "no"

if [ "$fail" -eq 0 ]; then
  printf 'test-recovery-classify: PASS (6/6)\n'
fi
exit "$fail"
