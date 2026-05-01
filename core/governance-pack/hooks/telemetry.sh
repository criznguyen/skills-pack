#!/usr/bin/env bash
# telemetry.sh — PostToolUse hook (matcher: .*).
#
# Trigger: PostToolUse on every tool call.
# Behavior:
#   - Reads tool input JSON from stdin.
#   - Appends a JSONL line to $GOVERNANCE_PACK_TELEMETRY_FILE
#     (default: ~/.claude/telemetry.jsonl).
#   - One line per tool call: { ts, tool_name, session_id, project, success, exit_code }.
#   - Truncates payload — never persists tool_input (may contain secrets).
#   - Idempotent + graceful: any failure → exit 0, never blocks.
#
# Privacy: telemetry stays LOCAL. No network. Rotate/prune at user discretion;
# install.sh does NOT enable any upload. To disable entirely:
#   export GOVERNANCE_PACK_TELEMETRY=0
#
# Composes with: nothing — runs after all other PostToolUse hooks. Safe to
# layer with core-config/lint-touched.sh.

set -uo pipefail
trap 'exit 0' ERR EXIT

# Honor opt-out.
case "${GOVERNANCE_PACK_TELEMETRY:-1}" in
  0|false|FALSE|no|NO) exit 0 ;;
esac

OUT_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME/.claude/telemetry.jsonl}"
OUT_DIR="$(dirname "$OUT_FILE")"
[ -d "$OUT_DIR" ] || mkdir -p "$OUT_DIR" 2>/dev/null || exit 0

INPUT="$(cat || true)"

# Best-effort field extraction. Use jq if present, else python3.
emit_line() {
  local ts tool_name session_id success exit_code project
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  project="${CLAUDE_PROJECT_DIR:-${PWD}}"

  if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    tool_name="$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo unknown)"
    session_id="$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo)"
    success="$(echo "$INPUT" | jq -r '.tool_response.success // .success // ""' 2>/dev/null || echo)"
    exit_code="$(echo "$INPUT" | jq -r '.tool_response.exit_code // ""' 2>/dev/null || echo)"
  elif [ -n "$INPUT" ] && command -v python3 >/dev/null 2>&1; then
    read -r tool_name session_id success exit_code < <(echo "$INPUT" | python3 -c '
import json,sys
try:
  d=json.load(sys.stdin)
  resp=d.get("tool_response",{}) if isinstance(d.get("tool_response"),dict) else {}
  print(d.get("tool_name","unknown"),
        d.get("session_id",""),
        resp.get("success", d.get("success","")),
        resp.get("exit_code",""))
except Exception:
  print("unknown","","","")
' 2>/dev/null)
  else
    tool_name="unknown"
    session_id=""
    success=""
    exit_code=""
  fi

  # Build JSONL via printf so we never depend on jq for output.
  printf '{"ts":"%s","tool_name":"%s","session_id":"%s","project":"%s","success":"%s","exit_code":"%s"}\n' \
    "$ts" "${tool_name//\"/}" "${session_id//\"/}" "${project//\"/}" "${success//\"/}" "${exit_code//\"/}" \
    >> "$OUT_FILE" 2>/dev/null || true
}

# _check_debug_tags — feat:debug-tag-convention (charter §2.2 / §2.5).
# Warn-only PostToolUse advisory: emits a single stderr line prefixed
# `debug-tag:` when (a) Bash/Edit/Write tool input contains a debug-class
# string with no same-line `[DEBUG-<8-hex>]` tag, or (b) the tool is `Bash`
# invoking `git commit` and the staged diff still carries `[DEBUG-`.
# ALWAYS returns 0 — never blocks the hook chain. See
# core/governance-pack/CLAUDE.md and docs/sdlc/decisions/debug-tag-convention.md.
_check_debug_tags() {
  case "${GOVERNANCE_PACK_DEBUG_TAG_CHECK:-1}" in
    0|false|FALSE|no|NO) return 0 ;;
  esac

  local tool_name="" payload=""
  if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    tool_name="$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo)"
    payload="$(echo "$INPUT" | jq -r '.tool_input // {} | tostring' 2>/dev/null || echo)"
  else
    return 0
  fi
  case "$tool_name" in
    Bash|Edit|Write) ;;
    *) return 0 ;;
  esac

  # Canonical regex copied verbatim from core/governance-pack/CLAUDE.md §1.
  local debug_class='console\.(log|error|warn|debug|info)\(|[[:space:]]print\(|[[:space:]]dbg!\(|eprintln!\(|[[:space:]]println!\(|fmt\.Println\('
  local tag_re='\[DEBUG-[0-9a-f]{8}\]'

  if echo "$payload" | grep -qE "$debug_class" 2>/dev/null && \
     ! echo "$payload" | grep -qE "$tag_re" 2>/dev/null; then
    printf 'debug-tag: untagged debug-class string in %s tool input — prefix with [DEBUG-<8-hex>] for grep-able cleanup\n' "$tool_name" >&2
  fi

  if [ "$tool_name" = "Bash" ]; then
    local cmd=""
    cmd="$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo)"
    case "$cmd" in
      *'git commit'*)
        if command -v git >/dev/null 2>&1 && \
           git diff --cached --no-color 2>/dev/null | grep -qE "$tag_re" 2>/dev/null; then
          printf 'debug-tag: staged diff still contains [DEBUG-<hex>] tags — run cleanup grep before commit\n' >&2
        fi
        ;;
    esac
  fi
  return 0
}

emit_line
_check_debug_tags
exit 0
