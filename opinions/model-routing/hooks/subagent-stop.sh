#!/usr/bin/env bash
#
# CQR-C hook: SubagentStop
# Scan the sub-agent transcript tail and exit_status for refusal/failure signals.
# Emit an escalation hint to the parent if the sub-agent stopped abnormally.
# Always exit 0.
#
# Inputs (stdin JSON):
#   .session_id, .agent_id (or .subagent_id), .transcript_path, .exit_status (or .status)

set -euo pipefail

CQR_LOG_FILE="${CQR_LOG_FILE:-$HOME/.claude/cqr-hooks.log}"
CQR_STATE_DIR="${CQR_STATE_DIR:-$HOME/.claude/state}"
CQR_TRANSCRIPT_TAIL_BYTES="${CQR_TRANSCRIPT_TAIL_BYTES:-65536}"

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
  printf '%s [%s] %s\n' "$(date -Iseconds)" "subagent-stop" "$*" >> "$CQR_LOG_FILE" 2>/dev/null || true
}

cqr_warn() { printf '[cqr/subagent-stop] %s\n' "$*" >&2 || true; }

emit_advisory() {
  local ctx="$1"
  cqr_log "ADVISORY: $ctx"
  jq -nc --arg ctx "$ctx" \
    '{hookSpecificOutput: {hookEventName: "SubagentStop", additionalContext: $ctx}}'
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

session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"'                    2>/dev/null || printf 'unknown')"
agent_id="$(printf   '%s' "$input" | jq -r '.agent_id // .subagent_id // "unknown"'      2>/dev/null || printf 'unknown')"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // ""'                      2>/dev/null || printf '')"
exit_status="$(printf '%s' "$input" | jq -r '.exit_status // .status // ""'              2>/dev/null || printf '')"

# Refusal / failure patterns.
# Note: Anthropic models often emit Unicode curly apostrophe U+2019 (UTF-8
# bytes E2 80 99) instead of ASCII '. We normalize the haystack to ASCII
# before grepping so a single straight-apostrophe pattern matches both forms.
# Regression guard for AUDIT-005.
PATTERNS='I cannot|I am unable|I apologize, but|I'\''m unable|I cannot proceed|refus(e|ed|al)|insufficient context|need more information|hit context limit|token limit (reached|exceeded)|out of memory|killed|fatal error|stack overflow'

# Replace any U+2019 (E2 80 99) with ASCII apostrophe.
normalize_apostrophes() {
  sed $'s/\xe2\x80\x99/\x27/g'
}

needs_escalation="false"
reason=""

# Exit-status check (treat empty / "0" / "success" / "completed" as OK)
if [ -n "$exit_status" ]; then
  case "$exit_status" in
    0|success|completed|ok|done) ;;
    *)
      needs_escalation="true"
      reason="exit_status='$exit_status'"
      ;;
  esac
fi

# Transcript scan
if [ -n "$transcript" ] && [ -f "$transcript" ] && [ -r "$transcript" ]; then
  tail_excerpt="$(tail -c "$CQR_TRANSCRIPT_TAIL_BYTES" "$transcript" 2>/dev/null | normalize_apostrophes || true)"
  if [ -n "$tail_excerpt" ] && printf '%s' "$tail_excerpt" | grep -qiE "$PATTERNS"; then
    matched="$(printf '%s' "$tail_excerpt" | grep -ioE "$PATTERNS" | head -1)"
    needs_escalation="true"
    reason="${reason:+$reason; }refusal-pattern '$matched'"
  fi
elif [ -n "$transcript" ]; then
  cqr_warn "transcript not readable: $transcript"
fi

if [ "$needs_escalation" = "true" ]; then
  mkdir -p "$CQR_STATE_DIR" 2>/dev/null || true
  printf '%s subagent=%s session=%s reason=%s\n' \
    "$(date -Iseconds)" "$agent_id" "$session_id" "$reason" \
    >> "$CQR_STATE_DIR/subagent-debrief.log" 2>/dev/null || true
  # Set the carry-over escalate flag so user-prompt-submit picks it up next turn
  touch "$CQR_STATE_DIR/escalate-next-${session_id}.flag" 2>/dev/null || true

  emit_advisory "SUBAGENT-ESCALATE: sub-agent '$agent_id' stopped abnormally ($reason). If you intend to retry the same task or follow up, escalate to claude-opus-4-7. Do not re-spawn on the same downshifted model — that is the failure-cascade pattern."
else
  cqr_log "subagent ok agent=$agent_id session=$session_id"
fi

exit 0
