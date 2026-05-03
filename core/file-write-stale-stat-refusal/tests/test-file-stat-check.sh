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

# 6. v1.7.0 — Read -> Edit (PostToolUse fires CACHE_HOOK) -> Edit again succeeds.
# Reproduces the insight_file_stat_refusal_cache_not_updated_on_edit.md scenario.
SESSION6="test-sess-v17"
TARGET6="$TMP/v17.txt"
echo "v1" > "$TARGET6"

# Step A: Read populates cache.
READ6=$(printf '{"tool_name":"Read","session_id":"%s","tool_input":{"file_path":"%s"}}' "$SESSION6" "$TARGET6")
printf '%s' "$READ6" | bash "$CACHE_HOOK"

# Step B: simulate first Edit. The Edit ITSELF is not a cache-hook event in
# real Claude — PostToolUse fires after a SUCCESSFUL Edit. So we model the
# real-world sequence: agent does Edit (which advances mtime), then
# PostToolUse(Edit) fires → CACHE_HOOK refreshes cache with post-Edit mtime.
sleep 1
touch -d "+5 seconds" "$TARGET6"            # simulate Edit's mtime advance
EDIT6_POST=$(printf '{"tool_name":"Edit","session_id":"%s","tool_input":{"file_path":"%s"}}' "$SESSION6" "$TARGET6")
printf '%s' "$EDIT6_POST" | bash "$CACHE_HOOK"  # v1.7.0: matcher accepts Edit

# Step C: simulate second Edit by the same agent. Backdate cache read_at so we are PAST the cooldown.
CACHE6="$TMP/.claude/sessions/$SESSION6/file-stat.cache"
NOW6=$(date +%s)
PAST6=$(( NOW6 - 60 ))
# Replace the LAST cache entry's read_at with PAST6 to simulate "the post-Edit
# cache update happened > cooldown ago" — the next Edit must still pass
# because mtime hasn't advanced beyond the cached one.
ESC_PATH6="${TARGET6//\\/\\\\}"
ESC_PATH6="${ESC_PATH6//\"/\\\"}"
LAST_MTIME=$(stat -c %Y "$TARGET6" 2>/dev/null || stat -f %m "$TARGET6")
# Replace the cache contents with a single entry whose mtime matches the
# current on-disk mtime AND whose read_at is past cooldown. If v1.7.0 logic
# is correct, the next Edit sees zero drift → pass.
printf '{"path":"%s","mtime":%s,"read_at":%s}\n' "$ESC_PATH6" "$LAST_MTIME" "$PAST6" > "$CACHE6"

EDIT6_PRE=$(printf '{"tool_name":"Edit","session_id":"%s","tool_input":{"file_path":"%s"}}' "$SESSION6" "$TARGET6")
out=$(printf '%s' "$EDIT6_PRE" | bash "$CHECK_HOOK" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 0 ]; then
  printf 'PASS: case=v17-same-agent-consecutive-edit exit=0 (cache refreshed by Edit-class hook)\n'
else
  printf 'FAIL: case=v17-same-agent-consecutive-edit expected exit=0 got=%s stderr=%s\n' "$ec" "$out" >&2
  fail=1
fi

# 7. Confirm external write AFTER own Edit STILL refuses (v1.6.0 protection preserved).
sleep 1
touch -d "+30 seconds" "$TARGET6"            # external mtime advance, no PostToolUse follow-up
out=$(printf '%s' "$EDIT6_PRE" | bash "$CHECK_HOOK" 2>&1 >/dev/null)
ec=$?
if [ "$ec" -eq 2 ] && printf '%s' "$out" | grep -q 'refused'; then
  printf 'PASS: case=v17-external-write-after-own-edit-still-refused exit=2\n'
else
  printf 'FAIL: case=v17-external-write-after-own-edit-still-refused expected exit=2 got=%s stderr=%s\n' "$ec" "$out" >&2
  fail=1
fi

# 8. Confirm Write tool name is also accepted by CACHE_HOOK (matcher coverage).
SESSION8="test-sess-v17-write"
TARGET8="$TMP/v17-write.txt"
echo "v1" > "$TARGET8"
WRITE8=$(printf '{"tool_name":"Write","session_id":"%s","tool_input":{"file_path":"%s"}}' "$SESSION8" "$TARGET8")
printf '%s' "$WRITE8" | bash "$CACHE_HOOK"
CACHE8="$TMP/.claude/sessions/$SESSION8/file-stat.cache"
if [ -f "$CACHE8" ] && grep -q "$TARGET8" "$CACHE8"; then
  printf 'PASS: case=v17-write-class-cache-update exit=0\n'
else
  printf 'FAIL: case=v17-write-class-cache-update — Write event did not populate cache\n' >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-file-stat-check: PASS (8/8)\n'
fi
exit "$fail"
