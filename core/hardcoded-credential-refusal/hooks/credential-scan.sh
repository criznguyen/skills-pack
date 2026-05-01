#!/usr/bin/env bash
# credential-scan.sh — PreToolUse hook (matcher: Edit|Write|MultiEdit).
#
# Scans tool_input.new_string (Edit) / tool_input.content (Write) /
# tool_input.edits[*].new_string (MultiEdit) against
# templates/credential-regex-bank.txt. Refuses on match unless a
# `gitleaks:allow` marker comment appears within ±3 lines, OR the matched
# token is the official AWS docs example (AKIAIOSFODNN7EXAMPLE).
#
# Exit 2 on refusal; exit 0 on pass / bypass.
#
# Forbidden content (TM4): no LLM-spawn literals.
#
# Privacy invariant: telemetry never logs the matched substring, only the
# pattern name. The credential is what we are refusing — logging it would
# defeat the point.

set -uo pipefail

case "${HARDCODED_CREDENTIAL_REFUSAL_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

HOME_DIR="${HOME:-/root}"
HCR_DIR="${HARDCODED_CREDENTIAL_REFUSAL_DIR:-$HOME_DIR/.claude/hardcoded-credential-refusal}"
HCR_BANK="${HARDCODED_CREDENTIAL_REFUSAL_BANK:-$HCR_DIR/credential-regex-bank.txt}"
HCR_HOOKS_DIR="${HARDCODED_CREDENTIAL_REFUSAL_HOOKS_DIR:-$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null || exit 0

# Bank fallback: ship-source if install dest missing.
if [ ! -f "$HCR_BANK" ]; then
  CAND="$HCR_HOOKS_DIR/../templates/credential-regex-bank.txt"
  if [ -f "$CAND" ]; then HCR_BANK="$CAND"; else exit 0; fi
fi

# --- 1. Parse stdin ------------------------------------------------------
TOOL_NAME=""
FILE_PATH=""
NEW_CONTENT=""
SESSION_ID=""

if command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("")
    print("")
    print("")
    print("---END---")
    sys.exit(0)
ti = d.get("tool_input") or {}
if not isinstance(ti, dict): ti = {}
tn = d.get("tool_name", "") or ""
fp = ti.get("file_path", "") or ""
sid = d.get("session_id", "") or ""
if tn == "Edit":
    body = ti.get("new_string", "") or ""
elif tn == "Write":
    body = ti.get("content", "") or ""
elif tn == "MultiEdit":
    edits = ti.get("edits") or []
    parts = []
    if isinstance(edits, list):
        for e in edits:
            if isinstance(e, dict):
                ns = e.get("new_string", "")
                if ns: parts.append(ns)
    body = "\n".join(parts)
else:
    body = ""
print(tn)
print(fp)
print(sid)
print("---BODY---")
print(body)
print("---END---")
' 2>/dev/null)"
  TOOL_NAME="$(printf '%s' "$PARSED" | sed -n '1p')"
  FILE_PATH="$(printf '%s' "$PARSED" | sed -n '2p')"
  SESSION_ID="$(printf '%s' "$PARSED" | sed -n '3p')"
  NEW_CONTENT="$(printf '%s' "$PARSED" | sed -n '/^---BODY---$/,/^---END---$/p' | sed '1d;$d')"
elif command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"
  case "$TOOL_NAME" in
    Edit)      NEW_CONTENT="$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""')" ;;
    Write)     NEW_CONTENT="$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""')" ;;
    MultiEdit) NEW_CONTENT="$(printf '%s' "$INPUT" | jq -r '[(.tool_input.edits // [])[]?.new_string // ""] | join("\n")')" ;;
  esac
else
  exit 0
fi

case "$TOOL_NAME" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

[ -n "$NEW_CONTENT" ] || exit 0

emit_telemetry() {
  local decision="$1" pattern="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"event":"credential-scan","ts":"%s","tool":"%s","decision":"%s","matched_pattern":"%s","file_path":"%s","session_id":"%s"}\n' \
    "$ts" \
    "${TOOL_NAME//\"/}" \
    "${decision//\"/}" \
    "${pattern//\"/}" \
    "${FILE_PATH//\"/}" \
    "${SESSION_ID//\"/}" \
    >> "$TELEM_FILE" 2>/dev/null || true
}

# --- 2. Suppress official AWS-docs example (always-allow) ----------------
# AKIAIOSFODNN7EXAMPLE is the canonical AWS docs fake; emit pass.
if printf '%s' "$NEW_CONTENT" | grep -F -q 'AKIAIOSFODNN7EXAMPLE'; then
  # Strip the example before scanning so it does not trip the aws_access_key regex.
  NEW_CONTENT_FOR_SCAN="$(printf '%s' "$NEW_CONTENT" | sed 's/AKIAIOSFODNN7EXAMPLE//g')"
else
  NEW_CONTENT_FOR_SCAN="$NEW_CONTENT"
fi

# --- 3. Scan content -----------------------------------------------------
# For each pattern, check if it matches; if it does, look at the lines
# around the match for a `gitleaks:allow` marker.
# Patterns with a 3rd tab-field of `mode: telemetry` emit telemetry but do
# NOT block (Finding-S4-1: high-FP regexes like `high_entropy_hex`).
MATCHED_PATTERN=""
MATCHED_LINE_NO=0

while IFS=$'\t' read -r NAME REGEX MODE || [ -n "${NAME:-}" ]; do
  case "$NAME" in '#'*|'') continue ;; esac
  [ -n "${REGEX:-}" ] || continue
  MODE="${MODE:-refuse}"
  # Find the first matching line number.
  LINE_NO="$(printf '%s\n' "$NEW_CONTENT_FOR_SCAN" | grep -nE -- "$REGEX" 2>/dev/null | head -n1 | cut -d: -f1)"
  if [ -n "$LINE_NO" ]; then
    case "$MODE" in
      *telemetry*)
        # Record the signal but keep walking — do not block on this match.
        emit_telemetry "telemetry-match" "$NAME"
        continue
        ;;
    esac
    MATCHED_PATTERN="$NAME"
    MATCHED_LINE_NO="$LINE_NO"
    break
  fi
done < "$HCR_BANK"

if [ -z "$MATCHED_PATTERN" ]; then
  emit_telemetry "pass" ""
  exit 0
fi

# --- 4. Marker bypass: gitleaks:allow within ±3 lines of MATCHED_LINE_NO -
START=$((MATCHED_LINE_NO - 3))
END=$((MATCHED_LINE_NO + 3))
[ "$START" -lt 1 ] && START=1
WINDOW="$(printf '%s\n' "$NEW_CONTENT" | sed -n "${START},${END}p")"
if printf '%s' "$WINDOW" | grep -qi 'gitleaks:allow'; then
  emit_telemetry "bypass" "$MATCHED_PATTERN"
  printf '[credential-scan-bypass] pattern=%s file=%s line=%s (gitleaks:allow marker honored)\n' \
    "$MATCHED_PATTERN" "$FILE_PATH" "$MATCHED_LINE_NO" >&2
  exit 0
fi

# --- 5. Refuse -----------------------------------------------------------
emit_telemetry "refused" "$MATCHED_PATTERN"
printf '[credential-scan-refused] pattern=%s file=%s line=%s — refusing to write a hardcoded credential\n' \
  "$MATCHED_PATTERN" "$FILE_PATH" "$MATCHED_LINE_NO" >&2
printf 'If this is a legitimate test fixture or doc, add `// gitleaks:allow` within \xc2\xb13 lines of the value, OR set HARDCODED_CREDENTIAL_REFUSAL_DISABLE=1 for this session.\n' >&2
exit 2
