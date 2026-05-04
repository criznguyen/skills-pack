#!/usr/bin/env bash
# cache-mtime-on-read.sh — PostToolUse(Read|Edit|Write|MultiEdit).
#
# Appends {path,mtime,read_at} to ~/.claude/sessions/<session_id>/file-stat.cache
# every time the agent ITSELF interacts with a file (Reads or modifies it).
# Recording on Edit/Write/MultiEdit is required so consecutive same-agent
# edits don't false-positive "drift" via the PreToolUse stat check
# (the agent's own prior write would otherwise be flagged as external mtime
# advance). Source: insight_file_stat_refusal_cache_not_updated_on_edit.md.
#
# Race window: between the PreToolUse stat-check and this PostToolUse cache
# update is milliseconds; an external write that lands in that window slips
# past until the next agent action on the file.
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

# v1.7.0: refresh cache on Read AND on Edit/Write/MultiEdit so consecutive
# same-agent edits don't trip the drift check (the agent's own prior write
# advances mtime, which would otherwise look like external drift from the
# perspective of a Read-only cache).
case "$TOOL_NAME" in
  Read|Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac
[ -n "$FILE_PATH" ] || exit 0
[ -e "$FILE_PATH" ] || exit 0

CACHE_DIR="$HOME_DIR/.claude/sessions/$SESSION_ID"
CACHE_FILE="$CACHE_DIR/file-stat.cache"
[ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0

MTIME="$(stat -c %Y "$FILE_PATH" 2>/dev/null || stat -f %m "$FILE_PATH" 2>/dev/null || echo 0)"
NOW="$(date +%s 2>/dev/null || echo 0)"

ESC_PATH="${FILE_PATH//\\/\\\\}"
ESC_PATH="${ESC_PATH//\"/\\\"}"
ESC_SID="${SESSION_ID//\\/\\\\}"
ESC_SID="${ESC_SID//\"/\\\"}"
# v2.1: stamp last_writer_session_id so the PreToolUse stat-check can
# distinguish self-write drift (same session's lint/formatter touched the
# file post-cache via PostToolUse hook chain) from genuine cross-session
# drift. Backward compatible: missing session_id falls through to strict
# v2.0 behavior. Source: docs/research/v1.8-ideas/file-stat-refusal-same-session-bypass.md
printf '{"path":"%s","mtime":%s,"read_at":%s,"session_id":"%s"}\n' "$ESC_PATH" "${MTIME:-0}" "${NOW:-0}" "$ESC_SID" \
  >> "$CACHE_FILE" 2>/dev/null || true

exit 0
