#!/usr/bin/env bash
# test-file-stat-check.sh — 5-case unit suite.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
CACHE_HOOK="$REPO_ROOT/core/file-write-stale-stat-refusal/hooks/cache-mtime-on-read.sh"
CHECK_HOOK="$REPO_ROOT/core/file-write-stale-stat-refusal/hooks/file-stat-check.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export GOVERNANCE_PACK_TELEMETRY_FILE="$TMP/.claude/telemetry.jsonl"
mkdir -p "$TMP/.claude"

SESSION="test-sess"
TARGET="$TMP/file.txt"
echo "v1" > "$TARGET"

fail=0

# 1. No cache → pass (no-cache)
PAYLOAD=$(printf '{"tool_name":"Edit","session_id":"%s","tool_input":{"file_path":"%s"}}' "$SESSION" "$TARGET")
out=$(printf '%s' "$PAYLOAD" | bash "$CHECK_HOOK" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 0 ]; then
  printf 'PASS: case=no-cache exit=0\n'
else
  printf 'FAIL: case=no-cache expected exit=0 got=%s stderr=%s\n' "$ec" "$out" >&2
  fail=1
fi

# 2. Read populates cache → no drift → pass
READ_PAYLOAD=$(printf '{"tool_name":"Read","session_id":"%s","tool_input":{"file_path":"%s"}}' "$SESSION" "$TARGET")
printf '%s' "$READ_PAYLOAD" | bash "$CACHE_HOOK"

EDIT_PAYLOAD=$PAYLOAD
out=$(printf '%s' "$EDIT_PAYLOAD" | bash "$CHECK_HOOK" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 0 ]; then
  printf 'PASS: case=no-drift exit=0\n'
else
  printf 'FAIL: case=no-drift expected exit=0 got=%s stderr=%s\n' "$ec" "$out" >&2
  fail=1
fi

# 3. Within cooldown — modify mtime forward, but read_at is fresh → cooldown pass
sleep 1
touch -d "+10 seconds" "$TARGET"
out=$(printf '%s' "$EDIT_PAYLOAD" | bash "$CHECK_HOOK" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -q 'cooldown'; then
  printf 'PASS: case=within-cooldown exit=0 stderr~cooldown\n'
else
  printf 'FAIL: case=within-cooldown expected exit=0 cooldown advisory; got=%s stderr=%s\n' "$ec" "$out" >&2
  fail=1
fi

# 4. Past cooldown — backdate read_at to 60s ago, mtime drift → refuse
CACHE_FILE="$TMP/.claude/sessions/$SESSION/file-stat.cache"
NOW=$(date +%s)
PAST=$(( NOW - 60 ))
# Replace cache with backdated entry (mtime kept; read_at backdated)
ESC_PATH="${TARGET//\\/\\\\}"
ESC_PATH="${ESC_PATH//\"/\\\"}"
CURR_MTIME=$(stat -c %Y "$TARGET" 2>/dev/null || stat -f %m "$TARGET")
OLD_MTIME=$(( CURR_MTIME - 100 ))
printf '{"path":"%s","mtime":%s,"read_at":%s}\n' "$ESC_PATH" "$OLD_MTIME" "$PAST" > "$CACHE_FILE"

out=$(printf '%s' "$EDIT_PAYLOAD" | bash "$CHECK_HOOK" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 2 ] && printf '%s' "$out" | grep -q 'refused'; then
  printf 'PASS: case=stale-write exit=2 refused\n'
else
  printf 'FAIL: case=stale-write expected exit=2 refused; got=%s stderr=%s\n' "$ec" "$out" >&2
  fail=1
fi

# 5. Disable env var bypass
out=$(FILE_WRITE_STALE_STAT_REFUSAL_DISABLE=1 printf '%s' "$EDIT_PAYLOAD" | FILE_WRITE_STALE_STAT_REFUSAL_DISABLE=1 bash "$CHECK_HOOK" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 0 ]; then
  printf 'PASS: case=disable-flag exit=0\n'
else
  printf 'FAIL: case=disable-flag expected exit=0 got=%s\n' "$ec" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-file-stat-check: PASS (5/5)\n'
fi
exit "$fail"
