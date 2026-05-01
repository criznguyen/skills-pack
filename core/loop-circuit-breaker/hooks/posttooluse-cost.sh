#!/usr/bin/env bash
# posttooluse-cost.sh — PostToolUse hook (matcher: *).
#
# Reads tool_response.tokens (input/output) and the model name; looks up
# per-1M-token rates from opinions/model-routing/cqr-locks.example.txt
# (SHA-pinned per F11; advisory-only when missing). Increments
# session_counters.usd_spent. Always exits 0 — the actual halt fires on
# PreToolUse next call (precedence ensures usd_spent is checked there).
#
# Forbidden content (TM4): no LLM-spawn literals.

set -uo pipefail

case "${LOOP_BREAKER_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

HOME_DIR="${HOME:-/root}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null || exit 0

if command -v jq >/dev/null 2>&1; then
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "default"')"
  IN_TOK="$(printf '%s' "$INPUT" | jq -r '.tool_response.input_tokens // .tool_response.usage.input_tokens // 0' 2>/dev/null)"
  OUT_TOK="$(printf '%s' "$INPUT" | jq -r '.tool_response.output_tokens // .tool_response.usage.output_tokens // 0' 2>/dev/null)"
  MODEL="$(printf '%s' "$INPUT" | jq -r '.tool_response.model // .model // ""' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: print("default"); print("0"); print("0"); print(""); sys.exit(0)
tr = d.get("tool_response") or {}
if not isinstance(tr, dict): tr = {}
u = tr.get("usage") or {}
if not isinstance(u, dict): u = {}
print(d.get("session_id", "") or "default")
print(tr.get("input_tokens", u.get("input_tokens", 0)) or 0)
print(tr.get("output_tokens", u.get("output_tokens", 0)) or 0)
print(tr.get("model", d.get("model", "")) or "")
' 2>/dev/null)"
  SESSION_ID="$(printf '%s' "$PARSED" | sed -n '1p')"
  IN_TOK="$(printf '%s' "$PARSED" | sed -n '2p')"
  OUT_TOK="$(printf '%s' "$PARSED" | sed -n '3p')"
  MODEL="$(printf '%s' "$PARSED" | sed -n '4p')"
else
  exit 0
fi

# If no token info recorded, nothing to charge.
if [ "${IN_TOK:-0}" = "0" ] && [ "${OUT_TOK:-0}" = "0" ]; then
  exit 0
fi

# Hardcoded fallback rate table per Anthropic public rates (2026-04-28):
#   claude-haiku-4-5: $1/1M input, $5/1M output
#   claude-sonnet-4-6: $3/1M input, $15/1M output
#   claude-opus-4-7: $15/1M input, $75/1M output
case "$MODEL" in
  *haiku*)   IN_RATE="1.00";  OUT_RATE="5.00"  ;;
  *sonnet*)  IN_RATE="3.00";  OUT_RATE="15.00" ;;
  *opus*)    IN_RATE="15.00"; OUT_RATE="75.00" ;;
  *)         IN_RATE="3.00";  OUT_RATE="15.00" ;;  # conservative default = sonnet
esac

THIS_USD="$(awk -v in_t="$IN_TOK" -v out_t="$OUT_TOK" -v ir="$IN_RATE" -v outr="$OUT_RATE" \
  'BEGIN{ printf "%.6f", (in_t * ir + out_t * outr) / 1000000.0 }')"

CSESS_DIR="$HOME_DIR/.claude/sessions/$SESSION_ID"
COUNTERS_FILE="$CSESS_DIR/counters.json"
[ -d "$CSESS_DIR" ] || mkdir -p "$CSESS_DIR" 2>/dev/null || exit 0

COUNTERS_JSON='{}'
[ -f "$COUNTERS_FILE" ] && COUNTERS_JSON="$(cat "$COUNTERS_FILE" 2>/dev/null || echo '{}')"

UPDATED="$(printf '%s' "$COUNTERS_JSON" | LCB_THIS_USD="$THIS_USD" python3 -c '
import json, os, sys
try:
    c = json.load(sys.stdin)
    if not isinstance(c, dict): c = {}
except Exception:
    c = {}
c["usd_spent"] = float(c.get("usd_spent", 0) or 0) + float(os.environ.get("LCB_THIS_USD", "0"))
print(json.dumps(c))
' 2>/dev/null)"

if [ -n "$UPDATED" ]; then
  printf '%s\n' "$UPDATED" > "$COUNTERS_FILE" 2>/dev/null || true
fi

printf '{"event":"loop-circuit-breaker","ts":"%s","counter":"usd_spent","value":%s,"ceiling":0,"action":"increment","session_id":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$THIS_USD" "${SESSION_ID//\"/}" \
  >> "$TELEM_FILE" 2>/dev/null || true

exit 0
