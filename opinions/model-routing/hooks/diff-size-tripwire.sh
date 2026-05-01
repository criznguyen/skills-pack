#!/usr/bin/env bash
#
# CQR-C hook: PostToolUse (Edit | Write | MultiEdit)
# Count changed lines from the Edit/Write tool input. If total exceeds the
# threshold (default 150), set a session-scoped flag so the next turn's
# user-prompt-submit hook escalates the routing hint to Opus.
# Always exit 0.
#
# Inputs (stdin JSON):
#   .session_id, .tool_name,
#   .tool_input.{old_string, new_string, content, edits[].old_string, edits[].new_string}
#
# Threshold override: $CQR_DIFF_THRESHOLD (default 150).

set -euo pipefail

CQR_LOG_FILE="${CQR_LOG_FILE:-$HOME/.claude/cqr-hooks.log}"
CQR_STATE_DIR="${CQR_STATE_DIR:-$HOME/.claude/state}"
CQR_DIFF_THRESHOLD="${CQR_DIFF_THRESHOLD:-150}"

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
  printf '%s [%s] %s\n' "$(date -Iseconds)" "diff-size-tripwire" "$*" >> "$CQR_LOG_FILE" 2>/dev/null || true
}

cqr_warn() { printf '[cqr/diff-size-tripwire] %s\n' "$*" >&2 || true; }

emit_advisory() {
  local ctx="$1"
  cqr_log "ADVISORY: $ctx"
  jq -nc --arg ctx "$ctx" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
}

count_lines() {
  # Counts newline-terminated lines plus a trailing partial line if non-empty.
  local s="${1-}"
  if [ -z "$s" ]; then echo 0; return; fi
  local nl
  nl="$(printf '%s' "$s" | awk 'END{print NR}')"
  echo "${nl:-0}"
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

session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null || printf 'unknown')"
tool_name="$(printf  '%s' "$input" | jq -r '.tool_name // ""'         2>/dev/null || printf '')"
file_path="$(printf  '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || printf '')"

added=0
removed=0

case "$tool_name" in
  Edit)
    old_str="$(printf '%s' "$input" | jq -r '.tool_input.old_string // ""' 2>/dev/null || printf '')"
    new_str="$(printf '%s' "$input" | jq -r '.tool_input.new_string // ""' 2>/dev/null || printf '')"
    removed="$(count_lines "$old_str")"
    added="$(count_lines "$new_str")"
    ;;
  MultiEdit)
    # Sum across all edits[].old_string + new_string
    sums="$(printf '%s' "$input" | jq -r '
      (.tool_input.edits // [])
      | map((.old_string // "") + "\n" + (.new_string // ""))
      | join("\n")
    ' 2>/dev/null || printf '')"
    # Approximate: count total non-empty lines / 2 for added, /2 for removed
    total_lines="$(count_lines "$sums")"
    added=$((total_lines / 2))
    removed=$((total_lines - added))
    ;;
  Write)
    content="$(printf '%s' "$input" | jq -r '.tool_input.content // ""' 2>/dev/null || printf '')"
    added="$(count_lines "$content")"
    removed=0
    ;;
  *)
    exit 0
    ;;
esac

added="${added:-0}"
removed="${removed:-0}"
total=$((added + removed))

if [ "$total" -le "$CQR_DIFF_THRESHOLD" ]; then
  cqr_log "diff-size ok session=$session_id tool=$tool_name file=$file_path added=$added removed=$removed total=$total"
  exit 0
fi

mkdir -p "$CQR_STATE_DIR" 2>/dev/null || true
flag="$CQR_STATE_DIR/escalate-next-${session_id}.flag"
touch "$flag" 2>/dev/null || true

printf '%s session=%s tool=%s file=%s added=%s removed=%s total=%s threshold=%s\n' \
  "$(date -Iseconds)" "$session_id" "$tool_name" "$file_path" "$added" "$removed" "$total" "$CQR_DIFF_THRESHOLD" \
  >> "$CQR_STATE_DIR/diff-size.log" 2>/dev/null || true

cqr_log "DIFF-SIZE-TRIPWIRE total=$total threshold=$CQR_DIFF_THRESHOLD session=$session_id file=$file_path"

emit_advisory "DIFF-SIZE-TRIPWIRE: $total lines changed in $tool_name on $file_path (>$CQR_DIFF_THRESHOLD threshold). The next sub-agent spawn or substantive follow-up MUST use claude-opus-4-7. Large diffs correlate with cross-file/architectural change risk where Sonnet's SWE-bench-Pro gap (~20pp vs Opus) bites hardest."

exit 0
