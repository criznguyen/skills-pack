#!/usr/bin/env bash
# test-counters.sh — iteration ceiling + cost increment + summary.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
PRE_HOOK="$REPO_ROOT/core/loop-circuit-breaker/hooks/pretooluse-count-hash.sh"
POST_HOOK="$REPO_ROOT/core/loop-circuit-breaker/hooks/posttooluse-cost.sh"
STOP_HOOK="$REPO_ROOT/core/loop-circuit-breaker/hooks/stop-summary.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export GOVERNANCE_PACK_TELEMETRY_FILE="$TMP/.claude/telemetry.jsonl"
export LOOP_BREAKER_ITER_CEILING=5
export LOOP_BREAKER_USD_CEILING=1000.0
mkdir -p "$TMP/.claude"

SESSION="t-counters"

fail=0

# Fire the PreToolUse hook 5 times — should pass; on the 6th call, halt.
for i in 1 2 3 4 5; do
  PAYLOAD=$(printf '{"tool_name":"Read","session_id":"%s","tool_input":{"file_path":"/tmp/x%d.txt"}}' "$SESSION" "$i")
  if ! printf '%s' "$PAYLOAD" | bash "$PRE_HOOK" >/dev/null 2>/dev/null; then
    printf 'FAIL: iteration %s should pass; got non-zero exit\n' "$i" >&2
    fail=1
  fi
done

# 6th call → over ceiling 5 → halt exit 2.
PAYLOAD=$(printf '{"tool_name":"Read","session_id":"%s","tool_input":{"file_path":"/tmp/over.txt"}}' "$SESSION")
out=$(printf '%s' "$PAYLOAD" | bash "$PRE_HOOK" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 2 ] && printf '%s' "$out" | grep -q 'iteration_count'; then
  printf 'PASS: iteration ceiling halt at 6 (ceiling=5)\n'
else
  printf 'FAIL: iteration ceiling halt — got exit=%s stderr=%s\n' "$ec" "$out" >&2
  fail=1
fi

# Stop hook: should print summary and reset.
SP=$(printf '{"session_id":"%s"}' "$SESSION")
out=$(printf '%s' "$SP" | bash "$STOP_HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'loop-cb-summary'; then
  printf 'PASS: stop-summary printed\n'
else
  printf 'FAIL: stop-summary missing — stderr=%s\n' "$out" >&2
  fail=1
fi
if [ -f "$TMP/.claude/sessions/$SESSION/counters.json" ]; then
  printf 'FAIL: counters.json not reset by stop hook\n' >&2
  fail=1
else
  printf 'PASS: counters.json reset\n'
fi

# Cost hook: PostToolUse with token usage should increment usd_spent.
SESSION2="t-cost"
PAYLOAD=$(printf '{"tool_name":"Read","session_id":"%s","tool_response":{"input_tokens":1000000,"output_tokens":1000000,"model":"claude-opus-4-7"}}' "$SESSION2")
printf '%s' "$PAYLOAD" | bash "$POST_HOOK" >/dev/null 2>/dev/null
COUNTERS="$TMP/.claude/sessions/$SESSION2/counters.json"
if [ -f "$COUNTERS" ]; then
  USD=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("usd_spent",0))' "$COUNTERS")
  # Expected: 1M*15/1M + 1M*75/1M = 90.0
  EXPECTED=90
  if awk -v u="$USD" -v e="$EXPECTED" 'BEGIN{exit !(u >= e-1 && u <= e+1)}'; then
    printf 'PASS: cost hook usd_spent=%s (expected ~%s)\n' "$USD" "$EXPECTED"
  else
    printf 'FAIL: cost hook usd_spent=%s expected ~%s\n' "$USD" "$EXPECTED" >&2
    fail=1
  fi
else
  printf 'FAIL: cost hook did not write counters.json\n' >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-counters: PASS\n'
fi
exit "$fail"
