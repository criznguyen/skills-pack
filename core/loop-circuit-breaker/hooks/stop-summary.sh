#!/usr/bin/env bash
# stop-summary.sh — Stop hook. Prints session summary; resets counters.
#
# Forbidden content (TM4): no LLM-spawn literals.

set -uo pipefail

case "${LOOP_BREAKER_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
HOME_DIR="${HOME:-/root}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"

SESSION_ID="default"
if [ -n "$INPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "default"')"
  elif command -v python3 >/dev/null 2>&1; then
    SESSION_ID="$(printf '%s' "$INPUT" | python3 -c '
import json,sys
try: print(json.load(sys.stdin).get("session_id", "default") or "default")
except Exception: print("default")
' 2>/dev/null)"
  fi
fi

CSESS_DIR="$HOME_DIR/.claude/sessions/$SESSION_ID"
COUNTERS_FILE="$CSESS_DIR/counters.json"

if [ ! -f "$COUNTERS_FILE" ]; then
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  LCB_COUNTERS_FILE="$COUNTERS_FILE" python3 -c '
import json, os, sys
path = os.environ.get("LCB_COUNTERS_FILE", "")
try:
    c = json.load(open(path))
except Exception:
    sys.exit(0)
# v1.7.0: surface read_count and write_count alongside iteration_count.
msg = "[loop-cb-summary] iteration_count={}/{} read_count={}/{} write_count={}/{} usd_spent={:.4f}/{:.2f} hash_collisions={} session={}".format(
    c.get("iteration_count", 0),
    c.get("iteration_ceiling", 0),
    c.get("read_count", 0),
    c.get("read_ceiling", 0),
    c.get("write_count", 0),
    c.get("write_ceiling", 0),
    float(c.get("usd_spent", 0) or 0),
    float(c.get("usd_ceiling", 0) or 0),
    c.get("hash_collisions", 0),
    c.get("session_id", ""),
)
sys.stderr.write(msg + "\n")
'
elif command -v jq >/dev/null 2>&1; then
  ITER="$(jq -r '.iteration_count // 0' "$COUNTERS_FILE")"
  CEIL="$(jq -r '.iteration_ceiling // 0' "$COUNTERS_FILE")"
  RC="$(jq -r '.read_count // 0' "$COUNTERS_FILE")"
  RCEIL="$(jq -r '.read_ceiling // 0' "$COUNTERS_FILE")"
  WC="$(jq -r '.write_count // 0' "$COUNTERS_FILE")"
  WCEIL="$(jq -r '.write_ceiling // 0' "$COUNTERS_FILE")"
  USD="$(jq -r '.usd_spent // 0' "$COUNTERS_FILE")"
  printf '[loop-cb-summary] iteration_count=%s/%s read_count=%s/%s write_count=%s/%s usd_spent=%s session=%s\n' \
    "$ITER" "$CEIL" "$RC" "$RCEIL" "$WC" "$WCEIL" "$USD" "$SESSION_ID" >&2
fi

# Reset counters.
rm -f "$COUNTERS_FILE" 2>/dev/null || true

printf '{"event":"loop-circuit-breaker","ts":"%s","counter":"summary","value":0,"ceiling":0,"action":"reset","session_id":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${SESSION_ID//\"/}" \
  >> "$TELEM_FILE" 2>/dev/null || true

exit 0
