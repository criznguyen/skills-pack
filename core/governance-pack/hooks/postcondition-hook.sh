#!/usr/bin/env bash
# postcondition-hook.sh — PostToolUse hook (matcher: Bash|Edit|Write|MultiEdit|NotebookEdit).
#
# Charter §2.1 enforcement upgrade (feat:postcondition-hook). F2-1 flat
# command-pattern table; F2-7 shadow-mode default (advisory, exit 0)
# with a documented one-line `jq` flip to blocking (exit 2).
#
# Behavior:
#   - Reads the PostToolUse JSON payload from stdin.
#   - Skips read-only tools and skipped task classes (early exit 0).
#   - Walks ~/.claude/postconditions.d/*.sh in lex order; runs the body
#     of every postcondition whose `# match=<tool>` and `# trigger=<glob>`
#     header line matches the current tool call.
#   - Each postcondition runs under `timeout` (default 5s, per-postcondition
#     `# timeout_override=<sec>` honoured up to 30s).
#   - Emits one JSONL line per postcondition execution (event=postcondition)
#     to ~/.claude/telemetry.jsonl + one stderr advisory line.
#   - Shadow-mode (default): always exits 0.
#   - Blocking-mode: exits 2 if any postcondition status != pass.
#
# Privacy: stdout from postcondition bodies is truncated to MAX_STDOUT_CHARS
# (default 200) before logging — never persists tool_input (matches
# telemetry.sh line 11 invariant).
#
# Composes with: telemetry.sh (PostToolUse `.*`) — both append to
# ~/.claude/telemetry.jsonl. Claude Code dispatches PostToolUse hooks
# sequentially per call so there is no race.

set -uo pipefail
# No ERR trap: postcondition bodies legitimately exit non-zero (= fail status)
# inside `$(timeout bash "$pc_file")` captures, and an ERR trap would short-
# circuit before we can record the JSONL line. Without `set -e` the script
# naturally continues past non-zero commands; explicit branches handle each
# expected RC. Fail-soft on unexpected shapes is via per-call `|| true`.

# Honor opt-out — operator escape hatch (US5).
case "${GOVERNANCE_PACK_POSTCONDITION_DISABLE:-0}" in
  1|true|TRUE|yes|YES) exit 0 ;;
esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

# --- 1. Resolve config paths -----------------------------------------------
HOME_DIR="${HOME:-/root}"
PC_DIR="${GOVERNANCE_PACK_POSTCONDITIONS_DIR:-$HOME_DIR/.claude/postconditions.d}"
PC_CONF="${GOVERNANCE_PACK_POSTCONDITIONS_CONF:-$HOME_DIR/.claude/postconditions.json}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null || exit 0

# Postconditions dir absent → nothing to enforce; silent skip.
[ -d "$PC_DIR" ] || exit 0

# --- 2. Parse stdin payload ------------------------------------------------
TOOL_NAME=""
TOOL_FILE_PATH=""
TOOL_COMMAND=""
TOOL_EXIT_CODE=""
TOOL_STDOUT_FILE=""
SESSION_ID=""

if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo)"
  TOOL_FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo)"
  TOOL_COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo)"
  TOOL_EXIT_CODE="$(printf '%s' "$INPUT" | jq -r '.tool_response.exit_code // ""' 2>/dev/null || echo)"
  TOOL_STDOUT_FILE="$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout_file // ""' 2>/dev/null || echo)"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo)"
elif command -v python3 >/dev/null 2>&1; then
  read -r TOOL_NAME TOOL_FILE_PATH TOOL_COMMAND TOOL_EXIT_CODE TOOL_STDOUT_FILE SESSION_ID < <(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("", "", "", "", "", "")
    sys.exit(0)
ti = d.get("tool_input") or {}
tr = d.get("tool_response") or {}
if not isinstance(ti, dict): ti = {}
if not isinstance(tr, dict): tr = {}
def s(x):
    return ("" if x is None else str(x)).replace("\n", " ").replace("\t", " ")
print(s(d.get("tool_name", "")), s(ti.get("file_path", "")), s(ti.get("command", "")),
      s(tr.get("exit_code", "")), s(tr.get("stdout_file", "")), s(d.get("session_id", "")))
' 2>/dev/null)
else
  exit 0  # No JSON parser available; fail-soft.
fi

# --- 3. Filter on state-changing tool list (NG3) --------------------------
case "$TOOL_NAME" in
  Bash|Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

# --- 4. Source the classifier library ------------------------------------
HOOKS_DIR_CANDIDATES=(
  "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
  "$HOME_DIR/.claude/hooks/governance-pack"
  "${GOVERNANCE_PACK_HOOKS_DIR:-}"
)
TASK_CLASS="unknown"
SPEC_ID=""
for d in "${HOOKS_DIR_CANDIDATES[@]}"; do
  [ -z "$d" ] && continue
  if [ -f "$d/_lib-audit-classify.sh" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$d/_lib-audit-classify.sh" 2>/dev/null || continue
    TASK_CLASS="$(infer_task_class_from_head 2>/dev/null || echo unknown)"
    SPEC_ID="$(infer_audit_id 2>/dev/null || echo "")"
    break
  fi
done

# --- 5. Read mode config (fail-soft to shadow defaults) ------------------
MODE="shadow"
TIMEOUT_SECONDS="5"
MAX_STDOUT_CHARS="200"
DEFAULT_CLASS_GATE_DEFAULT="feature system-change forced unknown"
DEFAULT_CLASS_GATE="$DEFAULT_CLASS_GATE_DEFAULT"
if [ -f "$PC_CONF" ]; then
  if command -v jq >/dev/null 2>&1; then
    M_TMP="$(jq -r '.mode // "shadow"' "$PC_CONF" 2>/dev/null || echo)"
    case "$M_TMP" in
      shadow|blocking) MODE="$M_TMP" ;;
    esac
    T_TMP="$(jq -r '.timeout_seconds // 5' "$PC_CONF" 2>/dev/null || echo)"
    case "$T_TMP" in
      ''|*[!0-9]*) ;;
      *) [ "$T_TMP" -gt 0 ] && [ "$T_TMP" -le 30 ] && TIMEOUT_SECONDS="$T_TMP" ;;
    esac
    S_TMP="$(jq -r '.max_stdout_chars // 200' "$PC_CONF" 2>/dev/null || echo)"
    case "$S_TMP" in
      ''|*[!0-9]*) ;;
      *) [ "$S_TMP" -gt 0 ] && [ "$S_TMP" -le 4096 ] && MAX_STDOUT_CHARS="$S_TMP" ;;
    esac
    G_TMP="$(jq -r '.default_class_gate // [] | join(" ")' "$PC_CONF" 2>/dev/null || echo)"
    [ -n "$G_TMP" ] && DEFAULT_CLASS_GATE="$G_TMP"
  fi
fi

# --- 6. Class-gate filter --------------------------------------------------
emit_telemetry() {
  # Args: status pc_name reason duration_ms
  local status="$1" pc="$2" reason="$3" dur="$4"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Truncate reason to MAX_STDOUT_CHARS, scrub newlines/quotes.
  reason="$(printf '%s' "$reason" | head -c "$MAX_STDOUT_CHARS" | tr -d '\n\r' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"event":"postcondition","ts":"%s","tool":"%s","postcondition":"%s","status":"%s","reason":"%s","mode":"%s","class":"%s","spec_id":"%s","duration_ms":%s,"session_id":"%s"}\n' \
    "$ts" \
    "${TOOL_NAME//\"/}" \
    "${pc//\"/}" \
    "$status" \
    "$reason" \
    "$MODE" \
    "${TASK_CLASS//\"/}" \
    "${SPEC_ID//\"/}" \
    "${dur:-0}" \
    "${SESSION_ID//\"/}" \
    >> "$TELEM_FILE" 2>/dev/null || true
}

emit_stderr() {
  # Args: status pc reason
  local status="$1" pc="$2" reason="$3"
  reason="$(printf '%s' "$reason" | head -c "$MAX_STDOUT_CHARS" | tr -d '\n\r')"
  printf '[postcondition-%s] tool=%s pc=%s mode=%s class=%s reason=%s\n' \
    "$status" "$TOOL_NAME" "$pc" "$MODE" "$TASK_CLASS" "$reason" >&2
}

# Class gate: skip if current class not in gate list.
class_in_gate=0
for c in $DEFAULT_CLASS_GATE; do
  [ "$c" = "$TASK_CLASS" ] && class_in_gate=1 && break
done
if [ "$class_in_gate" -eq 0 ]; then
  emit_telemetry "skipped" "_class-gate" "class=$TASK_CLASS not in gate" 0
  exit 0
fi

# --- 7. Walk postconditions.d/*.sh ----------------------------------------
ANY_FAIL=0
RAN_ANY=0

# Glob expansion may yield literal '*.sh' if dir is empty; guard with nullglob-equivalent.
shopt -s nullglob 2>/dev/null || true
PC_FILES=("$PC_DIR"/*.sh)
if [ "${#PC_FILES[@]}" -eq 0 ]; then
  exit 0
fi

# fnmatch_glob: bash `case` does fnmatch-style globbing; wrap as a function for clarity.
fnmatch_glob() {
  local pat="$1" str="$2"
  case "$str" in
    $pat) return 0 ;;
    *) return 1 ;;
  esac
}

for pc_file in "${PC_FILES[@]}"; do
  [ -f "$pc_file" ] || continue
  pc_name="$(basename "$pc_file")"

  # Skip the authoring template — its body is illustrative.
  case "$pc_name" in
    _template.sh) continue ;;
  esac

  # Extract header lines (only `# key=value` lines before the first non-comment line).
  match_tool=""
  trigger_glob=""
  verify_substring=""
  timeout_override=""
  while IFS= read -r line; do
    case "$line" in
      '#!'*) continue ;;
      '#'*=*)
        key="${line#\# }"; key="${key%%=*}"; key="${key// /}"
        val="${line#*=}"
        case "$key" in
          match) match_tool="$val" ;;
          trigger) trigger_glob="$val" ;;
          verify_substring) verify_substring="$val" ;;
          timeout_override) timeout_override="$val" ;;
        esac
        ;;
      '#'*|'') continue ;;
      *) break ;;
    esac
  done < "$pc_file"

  # Must declare at least match + trigger.
  [ -z "$match_tool" ] && continue
  [ -z "$trigger_glob" ] && continue

  # Match filter: tool must match.
  [ "$match_tool" = "$TOOL_NAME" ] || continue

  # Trigger filter: bash-glob against `command + file_path`.
  trigger_str="${TOOL_COMMAND}${TOOL_FILE_PATH}"
  if [ "$trigger_glob" != "*" ]; then
    fnmatch_glob "$trigger_glob" "$trigger_str" || continue
  fi

  # Per-postcondition timeout (capped at 30s, default TIMEOUT_SECONDS).
  TOVR="$TIMEOUT_SECONDS"
  case "$timeout_override" in
    ''|*[!0-9]*) ;;
    *)
      if [ "$timeout_override" -gt 0 ] && [ "$timeout_override" -le 30 ]; then
        TOVR="$timeout_override"
      fi
      ;;
  esac

  # Export env for the postcondition body.
  RAN_ANY=1
  start_ms="$(date +%s%3N 2>/dev/null || echo 0)"
  OUT=""
  RC=0
  # `timeout` from coreutils. If absent, fall back to direct bash exec
  # (Windows / minimal containers — TM3 §8 risk row).
  if command -v timeout >/dev/null 2>&1; then
    OUT="$(CLAUDE_TOOL_NAME="$TOOL_NAME" \
           CLAUDE_TOOL_INPUT_FILE_PATH="$TOOL_FILE_PATH" \
           CLAUDE_TOOL_INPUT_COMMAND="$TOOL_COMMAND" \
           CLAUDE_TOOL_EXIT_CODE="$TOOL_EXIT_CODE" \
           CLAUDE_TOOL_STDOUT_FILE="$TOOL_STDOUT_FILE" \
           timeout "${TOVR}s" bash "$pc_file" 2>&1)"
    RC=$?
  else
    OUT="$(CLAUDE_TOOL_NAME="$TOOL_NAME" \
           CLAUDE_TOOL_INPUT_FILE_PATH="$TOOL_FILE_PATH" \
           CLAUDE_TOOL_INPUT_COMMAND="$TOOL_COMMAND" \
           CLAUDE_TOOL_EXIT_CODE="$TOOL_EXIT_CODE" \
           CLAUDE_TOOL_STDOUT_FILE="$TOOL_STDOUT_FILE" \
           bash "$pc_file" 2>&1)"
    RC=$?
    OUT="${OUT}
[postcondition-hook] WARN: coreutils 'timeout' not found; ran without wall-clock guard"
  fi
  end_ms="$(date +%s%3N 2>/dev/null || echo 0)"
  if [ "${start_ms:-0}" -gt 0 ] && [ "${end_ms:-0}" -gt 0 ]; then
    DUR=$((end_ms - start_ms))
  else
    DUR=0
  fi

  # Determine status. coreutils `timeout` exits 124 on timeout.
  if [ "$RC" -eq 124 ]; then
    status="timeout"
    reason="timed out after ${TOVR}s"
    ANY_FAIL=1
  elif [ "$RC" -ne 0 ]; then
    status="fail"
    reason="$OUT"
    ANY_FAIL=1
  elif [ -n "$verify_substring" ] && ! printf '%s' "$OUT" | grep -qF -- "$verify_substring"; then
    status="fail"
    reason="verify_substring '$verify_substring' missing from stdout"
    ANY_FAIL=1
  else
    status="pass"
    reason=""
  fi

  emit_telemetry "$status" "$pc_name" "$reason" "$DUR"
  emit_stderr    "$status" "$pc_name" "$reason"
done

# --- 8. No matching postconditions → emit a single skipped record --------
# Why: distinguishes "tool ran, no postcondition matched" (covered by class
# gate or trigger filter) from "tool ran, postcondition matched and verified".
if [ "$RAN_ANY" -eq 0 ]; then
  emit_telemetry "skipped" "_no-match" "no postcondition matched tool=$TOOL_NAME" 0
  exit 0
fi

# --- 9. Final exit code per mode ------------------------------------------
if [ "$MODE" = "blocking" ] && [ "$ANY_FAIL" -eq 1 ]; then
  exit 2
fi
exit 0
