#!/usr/bin/env bash
# cache-mtime-on-read.sh — PostToolUse(Read). Appends {path,mtime,read_at}
# to ~/.claude/sessions/<session_id>/file-stat.cache.
#
# Forbidden content (TM4): no LLM-spawn literals.

set -uo pipefail

case "${FILE_WRITE_STALE_STAT_REFUSAL_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

HOME_DIR="${HOME:-/root}"

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

[ "$TOOL_NAME" = "Read" ] || exit 0
[ -n "$FILE_PATH" ] || exit 0
[ -e "$FILE_PATH" ] || exit 0

CACHE_DIR="$HOME_DIR/.claude/sessions/$SESSION_ID"
CACHE_FILE="$CACHE_DIR/file-stat.cache"
[ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0

MTIME="$(stat -c %Y "$FILE_PATH" 2>/dev/null || stat -f %m "$FILE_PATH" 2>/dev/null || echo 0)"
NOW="$(date +%s 2>/dev/null || echo 0)"

ESC_PATH="${FILE_PATH//\\/\\\\}"
ESC_PATH="${ESC_PATH//\"/\\\"}"
printf '{"path":"%s","mtime":%s,"read_at":%s}\n' "$ESC_PATH" "${MTIME:-0}" "${NOW:-0}" \
  >> "$CACHE_FILE" 2>/dev/null || true

exit 0
