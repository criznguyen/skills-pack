#!/usr/bin/env bash
# test-bypass-token.sh — bypass-token round-trip.
# Set ITER_CEILING=1; first call halts; bypass token allows the next call to pass.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
PRE_HOOK="$REPO_ROOT/core/loop-circuit-breaker/hooks/pretooluse-count-hash.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export GOVERNANCE_PACK_TELEMETRY_FILE="$TMP/.claude/telemetry.jsonl"
export LOOP_BREAKER_DIR="$TMP/.claude/loop-circuit-breaker"
export LOOP_BREAKER_ITER_CEILING=2
export LOOP_BREAKER_USD_CEILING=10000.0
mkdir -p "$TMP/.claude" "$LOOP_BREAKER_DIR"

# Seed bypass token.
TOKEN="abc123token"
echo "$TOKEN" > "$LOOP_BREAKER_DIR/bypass-token.sha"

SESSION="t-bypass"
fail=0

# 1st + 2nd call pass (under ceiling).
for i in 1 2; do
  PAYLOAD=$(printf '{"tool_name":"Read","session_id":"%s","tool_input":{"file_path":"/tmp/x%d.txt"}}' "$SESSION" "$i")
  if ! printf '%s' "$PAYLOAD" | bash "$PRE_HOOK" >/dev/null 2>/dev/null; then
    printf 'FAIL: call %s under ceiling should pass\n' "$i" >&2
    fail=1
  fi
done

# 3rd call without token → halt.
PAYLOAD=$(printf '{"tool_name":"Read","session_id":"%s","tool_input":{"file_path":"/tmp/over.txt"}}' "$SESSION")
ec=0; printf '%s' "$PAYLOAD" | bash "$PRE_HOOK" >/dev/null 2>/dev/null || ec=$?
if [ "$ec" -ne 2 ]; then
  printf 'FAIL: 3rd call without token should halt; got ec=%s\n' "$ec" >&2
  fail=1
else
  printf 'PASS: 3rd call halted as expected\n'
fi

# Same call WITH token → bypass passes.
out=$(LOOP_BREAKER_BYPASS_TOKEN="$TOKEN" printf '%s' "$PAYLOAD" | LOOP_BREAKER_BYPASS_TOKEN="$TOKEN" bash "$PRE_HOOK" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q 'loop-cb-bypass'; then
  printf 'PASS: bypass token allowed the call\n'
else
  printf 'FAIL: bypass token round-trip — ec=%s stderr=%s\n' "$ec" "$out" >&2
  fail=1
fi

# Wrong token → halt.
ec=0
out=$(LOOP_BREAKER_BYPASS_TOKEN="wrongtoken" printf '%s' "$PAYLOAD" | LOOP_BREAKER_BYPASS_TOKEN="wrongtoken" bash "$PRE_HOOK" 2>&1 >/dev/null) || ec=$?
if [ "$ec" -eq 2 ]; then
  printf 'PASS: wrong token rejected (halt)\n'
else
  printf 'FAIL: wrong token should halt; got ec=%s\n' "$ec" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-bypass-token: PASS\n'
fi
exit "$fail"
