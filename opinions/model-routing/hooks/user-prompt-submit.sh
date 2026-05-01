#!/usr/bin/env bash
#
# CQR-C hook: UserPromptSubmit
# Inject routing hints into the agent's context based on prompt + cwd content.
# Emits hookSpecificOutput.additionalContext per Claude Code hooks schema.
# Exit code is always 0 — this hook ADVISES, never blocks.
#
# Inputs (stdin JSON):
#   .session_id, .cwd, .user_message (or .prompt), .hook_event_name
#
# Override locks list via $CQR_LOCKS_FILE (default ~/.claude/cqr-locks.txt).

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
  printf '%s [%s] %s\n' "$(date -Iseconds)" "user-prompt-submit" "$*" >> "$CQR_LOG_FILE" 2>/dev/null || true
}

cqr_warn() { printf '[cqr/user-prompt-submit] %s\n' "$*" >&2 || true; }

emit_advisory() {
  local ctx="$1"
  cqr_log "ADVISORY: $ctx"
  jq -nc --arg ctx "$ctx" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
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

prompt="$(printf '%s' "$input" | jq -r '.user_message // .prompt // ""' 2>/dev/null || printf '')"
cwd="$(printf '%s'   "$input" | jq -r '.cwd // ""'                   2>/dev/null || printf '')"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null || printf 'unknown')"

# Defaults — overridable via cqr-locks.txt
DEFAULT_KEYWORDS='audit|security|production|threat model|refactor architecture|incident|compliance|migration|pci-?dss|gdpr|soc ?2'
DEFAULT_PATHS='/projects/fansipan/|/auth/|/security/|/billing/|/migrations/|docs/sdlc/security|docs/sdlc/principle-engineer'

KEYWORDS="$DEFAULT_KEYWORDS"
PATHS="$DEFAULT_PATHS"

if [ -f "$CQR_LOCKS_FILE" ]; then
  kw_lines="$(grep -E '^keyword:' "$CQR_LOCKS_FILE" 2>/dev/null | sed 's/^keyword://' | tr '\n' '|' | sed 's/|$//' || true)"
  path_lines="$(grep -E '^path:' "$CQR_LOCKS_FILE" 2>/dev/null | sed 's/^path://' | tr '\n' '|' | sed 's/|$//' || true)"
  [ -n "$kw_lines"   ] && KEYWORDS="$kw_lines"
  [ -n "$path_lines" ] && PATHS="$path_lines"
fi

# Session pin overrides everything
if [ -n "${CLAUDE_PIN_MODEL:-}" ]; then
  emit_advisory "ROUTING-HINT: session pin active — CLAUDE_PIN_MODEL=$CLAUDE_PIN_MODEL. Use this model for all sub-agent spawns this turn."
  exit 0
fi

# Carry-over: if a previous turn set the escalate flag, surface it
mkdir -p "$CQR_STATE_DIR" 2>/dev/null || true
escalate_flag="$CQR_STATE_DIR/escalate-next-${session_id}.flag"
lock_flag="$CQR_STATE_DIR/lock-opus.flag"
tripwire_counter="$CQR_STATE_DIR/tripwire-${session_id}.txt"

if [ -f "$escalate_flag" ] || [ -f "$lock_flag" ]; then
  reason=""
  [ -f "$escalate_flag" ] && reason="diff-size-tripwire flag from previous turn"
  [ -f "$lock_flag" ]     && reason="${reason:+$reason; }lock-opus flag from previous turn"
  rm -f "$escalate_flag" "$lock_flag" 2>/dev/null || true
  emit_advisory "ROUTING-HINT: carry-over escalation — $reason. Use claude-opus-4-7 for any sub-agent spawn this turn."
  exit 0
fi

if [ -f "$tripwire_counter" ]; then
  count="$(wc -l < "$tripwire_counter" 2>/dev/null | tr -d ' ' || echo 0)"
  if [ "${count:-0}" -ge 2 ]; then
    emit_advisory "ROUTING-HINT: tripwire counter at $count failures this session. Use claude-opus-4-7 — do not retry on a downshifted model."
    exit 0
  fi
fi

# Keyword fence
if printf '%s' "$prompt" | grep -qiE "$KEYWORDS"; then
  matched_kw="$(printf '%s' "$prompt" | grep -ioE "$KEYWORDS" | head -1)"
  emit_advisory "ROUTING-HINT: hard-locked Opus zone — keyword '$matched_kw' detected in prompt. Use claude-opus-4-7 for all sub-agent spawns this turn. Do not downshift to Sonnet/Haiku."
  exit 0
fi

# Path fence (cwd-based)
if [ -n "$cwd" ] && printf '%s' "$cwd" | grep -qE "$PATHS"; then
  matched_path="$(printf '%s' "$cwd" | grep -oE "$PATHS" | head -1)"
  emit_advisory "ROUTING-HINT: hard-locked Opus zone — cwd matches '$matched_path'. Use claude-opus-4-7 for all sub-agent spawns this turn."
  exit 0
fi

# Trivial heuristic — read-only / single-file rename / summarize
if printf '%s' "$prompt" | grep -qiE '^[[:space:]]*(grep|find|list|read|cat|show|which file|where is|summarize|rename|typo|ls)\b'; then
  emit_advisory "ROUTING-HINT: prompt looks trivial (read/grep/list/summarize pattern). Consider claude-haiku-4-5 for sub-agent spawns. Escalate if scope expands beyond single file."
  exit 0
fi

# Small heuristic — bounded edit
if printf '%s' "$prompt" | grep -qiE '^[[:space:]]*(fix|tweak|update|adjust|simplify|format|reword|clarify)\b'; then
  emit_advisory "ROUTING-HINT: prompt looks small (single-file bounded edit). Consider claude-sonnet-4-6 for sub-agent spawns. Escalate to Opus if diff exceeds 150 LOC or test fails."
  exit 0
fi

# Feature heuristic — multi-file feature work
if printf '%s' "$prompt" | grep -qiE '\b(implement|add (a |an )?(endpoint|component|feature)|build (a|the))\b'; then
  emit_advisory "ROUTING-HINT: prompt suggests multi-file feature work. Default to claude-sonnet-4-6 if scope is 2-5 files; escalate to claude-opus-4-7 once >5 files or cross-language."
  exit 0
fi

cqr_log "no-signal session=$session_id (Opus default applies)"
exit 0
