#!/usr/bin/env bash
# recovery-classify.sh — opt-in PostToolUse hook (matcher: Bash|Edit|Write).
#
# Reads tool_response.stderr from the PostToolUse JSON payload, matches it
# against templates/recovery-classes.tsv, and emits a single
# [RECOVERY-HINT: class=<class> action=<primitive>] advisory through
# hookSpecificOutput.additionalContext when exactly ONE class matches
# (confidence=1.0). Multi-class matches are suppressed (silence > guess).
#
# Always exits 0 (advisory mode).
#
# Forbidden content (TM4 / NG6): no LLM-spawn literals — see
# tests/test-no-claude-spawn.sh. Hook is shell + jq + python3-fallback +
# grep only. No daemon, no cache; the TSV is read every invocation.
#
# Privacy invariant: the telemetry JSONL line records class + primitive +
# confidence + latency, NEVER the stderr body. Mirrors quarantine-pack AC6.

set -uo pipefail

case "${RECOVERY_CLASS_FRAGMENT_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

HOME_DIR="${HOME:-/root}"
RC_HOOKS_DIR="${RECOVERY_CLASS_FRAGMENT_HOOKS_DIR:-$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")}"
RC_TSV="${RECOVERY_CLASS_FRAGMENT_TSV:-$RC_HOOKS_DIR/recovery-classes.tsv}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null || exit 0

# TSV missing → silent skip (hook is opt-in; no TSV = no classifier).
[ -f "$RC_TSV" ] || exit 0

START_MS="$(date +%s%3N 2>/dev/null || echo 0)"

# --- 1. Parse stdin payload ----------------------------------------------
TOOL_NAME=""
SESSION_ID=""
STDERR_RAW=""

if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo)"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo)"
  STDERR_RAW="$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // ""' 2>/dev/null || echo)"
elif command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("")
    print("")
    print("")
    sys.exit(0)
tr = d.get("tool_response") or {}
if not isinstance(tr, dict): tr = {}
print(d.get("tool_name", "") or "")
print(d.get("session_id", "") or "")
print(tr.get("stderr", "") or "")
' 2>/dev/null)"
  TOOL_NAME="$(printf '%s' "$PARSED" | sed -n '1p')"
  SESSION_ID="$(printf '%s' "$PARSED" | sed -n '2p')"
  STDERR_RAW="$(printf '%s' "$PARSED" | sed -n '3,$p')"
else
  exit 0
fi

# --- 2. Filter on matcher list -------------------------------------------
case "$TOOL_NAME" in
  Bash|Edit|Write) ;;
  *) exit 0 ;;
esac

# Empty stderr → nothing to classify.
[ -z "$STDERR_RAW" ] && exit 0

# --- 3. TSV match (case-insensitive substring) ---------------------------
# Build a list of matching classes; if exactly one unique class matches,
# emit hint. Otherwise silent.
STDERR_LC="$(printf '%s' "$STDERR_RAW" | tr '[:upper:]' '[:lower:]')"

MATCHED_CLASSES=""
MATCHED_PRIMITIVE=""
while IFS=$'\t' read -r CLASS PRIMITIVE PATTERN _ACTION; do
  case "$CLASS" in '#'*|'') continue ;; esac
  [ -n "$PATTERN" ] || continue
  PATTERN_LC="$(printf '%s' "$PATTERN" | tr '[:upper:]' '[:lower:]')"
  case "$STDERR_LC" in
    *"$PATTERN_LC"*)
      case ":$MATCHED_CLASSES:" in
        *":$CLASS:"*) ;;
        *)
          MATCHED_CLASSES="${MATCHED_CLASSES:+$MATCHED_CLASSES:}$CLASS"
          MATCHED_PRIMITIVE="$PRIMITIVE"
          ;;
      esac
      ;;
  esac
done < "$RC_TSV"

CLASS_COUNT=0
if [ -n "$MATCHED_CLASSES" ]; then
  # Count colon-separated entries (1 entry = 0 colons; n entries = n-1 colons).
  COLONS="${MATCHED_CLASSES//[^:]/}"
  CLASS_COUNT=$(( ${#COLONS} + 1 ))
fi

END_MS="$(date +%s%3N 2>/dev/null || echo 0)"
if [ "${START_MS:-0}" -gt 0 ] && [ "${END_MS:-0}" -gt 0 ]; then
  DUR=$((END_MS - START_MS))
else
  DUR=0
fi

emit_telemetry() {
  local class="$1" primitive="$2" confidence="$3"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"event":"recovery-class","ts":"%s","tool":"%s","class":"%s","primitive":"%s","confidence":%s,"latency_ms":%s,"session_id":"%s"}\n' \
    "$ts" \
    "${TOOL_NAME//\"/}" \
    "${class//\"/}" \
    "${primitive//\"/}" \
    "$confidence" \
    "${DUR:-0}" \
    "${SESSION_ID//\"/}" \
    >> "$TELEM_FILE" 2>/dev/null || true
}

if [ "$CLASS_COUNT" -ne 1 ]; then
  # Multi-class or no-match → silent. Log telemetry only when no class matched.
  emit_telemetry "ambiguous" "none" "0"
  exit 0
fi

CLASS_FINAL="$MATCHED_CLASSES"
PRIMITIVE_FINAL="$MATCHED_PRIMITIVE"

emit_telemetry "$CLASS_FINAL" "$PRIMITIVE_FINAL" "1"
printf '[recovery-class] tool=%s class=%s primitive=%s\n' "$TOOL_NAME" "$CLASS_FINAL" "$PRIMITIVE_FINAL" >&2

NOTICE="[RECOVERY-HINT: class=$CLASS_FINAL action=$PRIMITIVE_FINAL — see core/recovery-class-fragment/CLAUDE.md for the 4-class taxonomy]"

if command -v jq >/dev/null 2>&1; then
  printf '%s' "$NOTICE" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}'
elif command -v python3 >/dev/null 2>&1; then
  NOTICE_JSON="$(printf '%s' "$NOTICE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "${NOTICE//\"/\\\"}")"
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$NOTICE_JSON"
else
  ESC="${NOTICE//\\/\\\\}"
  ESC="${ESC//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$ESC"
fi

exit 0
