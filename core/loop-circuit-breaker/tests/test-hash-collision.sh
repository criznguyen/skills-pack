#!/usr/bin/env bash
# test-hash-collision.sh — 3 identical canonical tool calls in 10-call
# rolling window should halt with hash_collisions counter.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
PRE_HOOK="$REPO_ROOT/core/loop-circuit-breaker/hooks/pretooluse-count-hash.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export GOVERNANCE_PACK_TELEMETRY_FILE="$TMP/.claude/telemetry.jsonl"
export LOOP_BREAKER_ITER_CEILING=10000
export LOOP_BREAKER_USD_CEILING=10000.0
mkdir -p "$TMP/.claude"

SESSION="t-hash"
fail=0

# Identical canonical (Read with file_path) — fire 3 times.
PAYLOAD=$(printf '{"tool_name":"Read","session_id":"%s","tool_input":{"file_path":"/tmp/x.txt"}}' "$SESSION")
for i in 1 2; do
  if ! printf '%s' "$PAYLOAD" | bash "$PRE_HOOK" >/dev/null 2>/dev/null; then
    printf 'FAIL: collision call %s should pass — counters=%s\n' "$i" "$(cat "$TMP/.claude/sessions/$SESSION/counters.json" 2>/dev/null)" >&2
    fail=1
  fi
done

# 3rd call → 3 identical hashes in window → halt.
out=$(printf '%s' "$PAYLOAD" | bash "$PRE_HOOK" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 2 ] && printf '%s' "$out" | grep -q 'hash_collisions'; then
  printf 'PASS: hash-collision halt at 3rd identical call\n'
else
  printf 'FAIL: expected hash_collisions halt; got exit=%s stderr=%s\n' "$ec" "$out" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-hash-collision: PASS\n'
fi
exit "$fail"
