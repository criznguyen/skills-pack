#!/usr/bin/env bash
# file-stat-check.sh — PreToolUse(Edit|Write|MultiEdit).
#
# Refuses writes when target file's mtime drifted since the agent last
# Read it (5-second cooldown to absorb race-condition jitter).
#
# Forbidden content (TM4): no LLM-spawn literals.

set -uo pipefail

case "${FILE_WRITE_STALE_STAT_REFUSAL_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

HOME_DIR="${HOME:-/root}"
COOLDOWN_SEC="${STALE_COOLDOWN_SEC:-5}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null || exit 0

if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "default"')"
elif command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: print(""); print(""); print("default"); sys.exit(0)
ti = d.get("tool_input") or {}
if not isinstance(ti, dict): ti = {}
print(d.get("tool_name", "") or "")
print(ti.get("file_path", "") or "")
print(d.get("session_id", "") or "default")
' 2>/dev/null)"
  TOOL_NAME="$(printf '%s' "$PARSED" | sed -n '1p')"
  FILE_PATH="$(printf '%s' "$PARSED" | sed -n '2p')"
  SESSION_ID="$(printf '%s' "$PARSED" | sed -n '3p')"
else
  exit 0
fi

case "$TOOL_NAME" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac
[ -n "$FILE_PATH" ] || exit 0

emit_telemetry() {
  local decision="$1" drift="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"event":"file-stat-check","ts":"%s","tool":"%s","decision":"%s","file_path":"%s","drift_seconds":%s,"session_id":"%s"}\n' \
    "$ts" \
    "${TOOL_NAME//\"/}" \
    "${decision//\"/}" \
    "${FILE_PATH//\"/}" \
    "${drift:-0}" \
    "${SESSION_ID//\"/}" \
    >> "$TELEM_FILE" 2>/dev/null || true
}

# File does not exist → fresh write; pass.
if [ ! -e "$FILE_PATH" ]; then
  emit_telemetry "pass" "0"
  exit 0
fi

CACHE_FILE="$HOME_DIR/.claude/sessions/$SESSION_ID/file-stat.cache"

# No cache → never Read; treat as fresh-creation. Pass.
if [ ! -f "$CACHE_FILE" ]; then
  emit_telemetry "no-cache" "0"
  exit 0
fi

# Find latest entry for this path. Last-line-wins.
LATEST=""
if command -v jq >/dev/null 2>&1; then
  LATEST="$(jq -c --arg p "$FILE_PATH" 'select(.path==$p)' "$CACHE_FILE" 2>/dev/null | tail -n1 || echo)"
fi
if [ -z "$LATEST" ]; then
  # python fallback: grep by JSON path field
  LATEST="$(grep -F "\"path\":\"$FILE_PATH\"" "$CACHE_FILE" 2>/dev/null | tail -n1 || echo)"
fi
if [ -z "$LATEST" ]; then
  emit_telemetry "no-cache" "0"
  exit 0
fi

CACHED_MTIME=0
CACHED_READ_AT=0
if command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "$LATEST" | python3 -c '
import json, sys
try: d = json.loads(sys.stdin.read())
except Exception: print("0"); print("0"); sys.exit(0)
print(int(d.get("mtime", 0) or 0))
print(int(d.get("read_at", 0) or 0))
' 2>/dev/null)"
  CACHED_MTIME="$(printf '%s' "$PARSED" | sed -n '1p')"
  CACHED_READ_AT="$(printf '%s' "$PARSED" | sed -n '2p')"
elif command -v jq >/dev/null 2>&1; then
  CACHED_MTIME="$(printf '%s' "$LATEST" | jq -r '.mtime // 0')"
  CACHED_READ_AT="$(printf '%s' "$LATEST" | jq -r '.read_at // 0')"
fi

CURRENT_MTIME="$(stat -c %Y "$FILE_PATH" 2>/dev/null || stat -f %m "$FILE_PATH" 2>/dev/null || echo 0)"
NOW="$(date +%s 2>/dev/null || echo 0)"

DRIFT=$(( CURRENT_MTIME - CACHED_MTIME ))
SINCE_READ=$(( NOW - CACHED_READ_AT ))

if [ "$DRIFT" -le 0 ]; then
  emit_telemetry "pass" "$DRIFT"
  exit 0
fi

if [ "$SINCE_READ" -le "$COOLDOWN_SEC" ]; then
  emit_telemetry "cooldown" "$DRIFT"
  printf '[file-stat-cooldown] file=%s drift=%ss within %ss cooldown\n' \
    "$FILE_PATH" "$DRIFT" "$COOLDOWN_SEC" >&2
  exit 0
fi

emit_telemetry "refused" "$DRIFT"
printf '[file-stat-refused] file=%s drift=%ss — file was modified by another process since you last Read it; re-read before editing\n' \
  "$FILE_PATH" "$DRIFT" >&2
printf 'Bypass: export FILE_WRITE_STALE_STAT_REFUSAL_DISABLE=1 (not recommended; the correct recovery is to re-Read the file first)\n' >&2
exit 2
