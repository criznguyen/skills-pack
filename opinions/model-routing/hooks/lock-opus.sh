#!/usr/bin/env bash
#
# CQR-C hook: PreToolUse (Edit | Write | Bash)
# Detect destructive shell commands and writes to hard-locked Opus zones.
# Sets a session lock flag and injects an advisory for the agent.
# Always exit 0 — hooks ADVISE; the agent is responsible for compliance.
#
# Inputs (stdin JSON):
#   .session_id, .tool_name, .tool_input.{file_path|command|...}
#
# Reads keyword/path/bash matchers from $CQR_LOCKS_FILE (default ~/.claude/cqr-locks.txt).

set -euo pipefail

CQR_LOG_FILE="${CQR_LOG_FILE:-$HOME/.claude/cqr-hooks.log}"
CQR_LOCKS_FILE="${CQR_LOCKS_FILE:-$HOME/.claude/cqr-locks.txt}"
CQR_STATE_DIR="${CQR_STATE_DIR:-$HOME/.claude/state}"

cqr_rotate_log() {
  [ -f "$CQR_LOG_FILE" ] || return 0
  local mtime now
  mtime="$(stat -c %Y "$CQR_LOG_FILE" 2>/dev/null || stat -f %m "$CQR_LOG_FILE" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  if [ "$((now - mtime))" -gt 604800 ]; then
    mv "$CQR_LOG_FILE" "${CQR_LOG_FILE}.$(date +%Y%m%d)" 2>/dev/null || true
  fi
}

cqr_log() {
  cqr_rotate_log
  printf '%s [%s] %s\n' "$(date -Iseconds)" "lock-opus" "$*" >> "$CQR_LOG_FILE" 2>/dev/null || true
}

cqr_warn() { printf '[cqr/lock-opus] %s\n' "$*" >&2 || true; }

emit_advisory() {
  local ctx="$1"
  cqr_log "ADVISORY: $ctx"
  jq -nc --arg ctx "$ctx" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
}

# --- main ---

if ! command -v jq >/dev/null 2>&1; then
  cqr_warn "jq not installed; skipping (graceful no-op)"
  exit 0
fi

input="$(cat 2>/dev/null || true)"
if [ -z "$input" ]; then
  cqr_warn "empty stdin; skipping"
  exit 0
fi

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""'                    2>/dev/null || printf '')"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""'         2>/dev/null || printf '')"
command="$(printf  '%s' "$input" | jq -r '.tool_input.command // ""'            2>/dev/null || printf '')"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"'           2>/dev/null || printf 'unknown')"

# Defaults — overridable via cqr-locks.txt
DEFAULT_PATHS='/projects/fansipan/|/auth/|/security/|/billing/|/migrations/|docs/sdlc/security|docs/sdlc/principle-engineer'
DEFAULT_BASH='rm -rf|git push --force|git push -f([[:space:]]|$)|git reset --hard|chmod -R|chown -R|dd if=|mkfs\.|drop database|drop table|truncate table'

PATHS="$DEFAULT_PATHS"
BASH_PATTERNS="$DEFAULT_BASH"

if [ -f "$CQR_LOCKS_FILE" ]; then
  path_lines="$(grep -E '^path:' "$CQR_LOCKS_FILE" 2>/dev/null | sed 's/^path://' | tr '\n' '|' | sed 's/|$//' || true)"
  bash_lines="$(grep -E '^bash:' "$CQR_LOCKS_FILE" 2>/dev/null | sed 's/^bash://' | tr '\n' '|' | sed 's/|$//' || true)"
  [ -n "$path_lines" ] && PATHS="$path_lines"
  [ -n "$bash_lines" ] && BASH_PATTERNS="$bash_lines"
fi

mkdir -p "$CQR_STATE_DIR" 2>/dev/null || true

triggered=""
reason=""

case "$tool_name" in
  Edit|Write|MultiEdit|NotebookEdit)
    if [ -n "$file_path" ] && printf '%s' "$file_path" | grep -qE "$PATHS"; then
      matched="$(printf '%s' "$file_path" | grep -oE "$PATHS" | head -1)"
      triggered="path"
      reason="sensitive path '$matched' (file=$file_path)"
    fi
    ;;
  Bash)
    if [ -n "$command" ] && printf '%s' "$command" | grep -qiE "$BASH_PATTERNS"; then
      matched="$(printf '%s' "$command" | grep -ioE "$BASH_PATTERNS" | head -1)"
      triggered="bash"
      reason="destructive command '$matched' (cmd=${command:0:80})"
    fi
    ;;
  *)
    exit 0
    ;;
esac

if [ -z "$triggered" ]; then
  exit 0
fi

# Set the session lock flag — user-prompt-submit.sh will surface it next turn
touch "$CQR_STATE_DIR/lock-opus.flag" 2>/dev/null || true
printf '%s lock=opus session=%s trigger=%s reason=%s\n' \
  "$(date -Iseconds)" "$session_id" "$triggered" "$reason" \
  >> "$CQR_STATE_DIR/lock.log" 2>/dev/null || true

emit_advisory "LOCK-OPUS: $reason. All sub-agents spawned this turn (and any retry on next turn) MUST use claude-opus-4-7. Do not delegate this work to Sonnet or Haiku."

exit 0
