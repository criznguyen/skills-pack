#!/usr/bin/env bash
#
# CQR-C hook: PostToolUse (Bash | Edit | Write)
# Detect tool failures from tool_response. Increment per-session counter.
# Emit escalation hint when counter reaches >= 2 within the session.
# Always exit 0.
#
# Inputs (stdin JSON):
#   .session_id, .tool_name, .tool_response (object or string), .is_error (optional)

set -euo pipefail

CQR_LOG_FILE="${CQR_LOG_FILE:-$HOME/.claude/cqr-hooks.log}"
CQR_STATE_DIR="${CQR_STATE_DIR:-$HOME/.claude/state}"
CQR_TRIPWIRE_THRESHOLD="${CQR_TRIPWIRE_THRESHOLD:-2}"

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
  printf '%s [%s] %s\n' "$(date -Iseconds)" "post-tool-use-failure" "$*" >> "$CQR_LOG_FILE" 2>/dev/null || true
}

cqr_warn() { printf '[cqr/post-tool-use-failure] %s\n' "$*" >&2 || true; }

emit_advisory() {
  local ctx="$1"
  cqr_log "ADVISORY: $ctx"
  jq -nc --arg ctx "$ctx" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
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

# tool_response can be an object, string, or array. Normalize to a searchable string.
response_str="$(printf '%s' "$input" \
  | jq -r '
      (.tool_response // .tool_result // "") as $r
      | if ($r | type) == "object" then ($r | tostring)
        elif ($r | type) == "array"  then ($r | tostring)
        else $r
        end
    ' 2>/dev/null || printf '')"

is_error="$(printf '%s' "$input" | jq -r '
    (.tool_response.is_error // .is_error // .tool_response.isError // .isError // false)
    | tostring
  ' 2>/dev/null || printf 'false')"

# Failure detection
#
# Primary signal: structured `is_error=true` on the tool result.
# Fallback signals: tightened keyword patterns that resist false positives like
#   "0 errors", "no errors found", "error rate: 0%", "error: 0".
# Each fallback pattern must match a real failure indicator anchored at line
# start, exit-code form, or a test-runner shape — never a bare "error" token.
failure="false"
matched_pattern=""

if [ "$is_error" = "true" ]; then
  failure="true"
  matched_pattern="is_error=true"
elif printf '%s' "$response_str" | grep -qE 'exit code [1-9][0-9]*'; then
  failure="true"
  matched_pattern="nonzero-exit-code"
elif printf '%s' "$response_str" | grep -qiE 'traceback \(most recent call last\)'; then
  failure="true"
  matched_pattern="python-traceback"
elif printf '%s' "$response_str" | grep -qE '(^|\\n)FAIL(:|ED)\b'; then
  failure="true"
  matched_pattern="fail-anchored"
elif printf '%s' "$response_str" | grep -qE 'command not found$'; then
  failure="true"
  matched_pattern="command-not-found"
elif printf '%s' "$response_str" | grep -qE '(^|\\n)E\s+'; then
  failure="true"
  matched_pattern="pytest-E-line"
elif printf '%s' "$response_str" | grep -qE '(✗|✘|AssertionError|test[s]? failed\b|[1-9][0-9]* failed)'; then
  failure="true"
  matched_pattern="test-failure-pattern"
fi

if [ "$failure" != "true" ]; then
  exit 0
fi

mkdir -p "$CQR_STATE_DIR" 2>/dev/null || true
counter_file="$CQR_STATE_DIR/tripwire-${session_id}.txt"

# Append failure record (one line = one failure)
printf '%s tool=%s pattern=%s\n' "$(date -Iseconds)" "$tool_name" "$matched_pattern" \
  >> "$counter_file" 2>/dev/null || true

count="$(wc -l < "$counter_file" 2>/dev/null | tr -d ' ' || echo 0)"
count="${count:-0}"

cqr_log "TRIPWIRE recorded session=$session_id tool=$tool_name pattern=$matched_pattern count=$count"

if [ "$count" -ge "$CQR_TRIPWIRE_THRESHOLD" ]; then
  emit_advisory "TRIPWIRE-ESCALATE: $count tool failures recorded in session $session_id (threshold=$CQR_TRIPWIRE_THRESHOLD). Next sub-agent spawn or retry MUST use claude-opus-4-7. Do not retry the same task on a downshifted model — failure mode #3/#4 from R1 (confident wrong code on Sonnet/Haiku)."
fi

exit 0
