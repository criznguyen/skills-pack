#!/usr/bin/env bash
# pretooluse-count-hash.sh — PreToolUse hook (matcher: *).
#
# Increments iteration_count, computes a canonical (tool_name + sorted keys)
# sha256 hash, maintains a rolling 10-call window of hashes, and counts
# collisions. Halts with exit 2 when:
#   1. iteration_count > iteration_ceiling
#   2. (usd_spent recorded by posttooluse-cost.sh) > usd_ceiling
#   3. hash_collisions >= 3 in current window
# Precedence per templates/precedence.md.
#
# Bypass: LOOP_BREAKER_BYPASS_TOKEN matching ~/.claude/loop-circuit-breaker/
# bypass-token.sha skips the check (single call). LOOP_BREAKER_DISABLE=1
# disables for the session.
#
# Forbidden content (TM4): no LLM-spawn literals.

set -uo pipefail

case "${LOOP_BREAKER_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

HOME_DIR="${HOME:-/root}"
LCB_DIR="${LOOP_BREAKER_DIR:-$HOME_DIR/.claude/loop-circuit-breaker}"
LCB_TOKEN_SHA="$LCB_DIR/bypass-token.sha"
ITER_CEILING="${LOOP_BREAKER_ITER_CEILING:-150}"
USD_CEILING="${LOOP_BREAKER_USD_CEILING:-25.0}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null || exit 0

if command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception:
    print(""); print("default"); print(""); sys.exit(0)
ti = d.get("tool_input") or {}
print(d.get("tool_name", "") or "")
print(d.get("session_id", "") or "default")
# Canonical = tool_name + sorted-keys-with-values JSON. Including values
# distinguishes (Read /a) from (Read /b) so different file paths do not
# collide in the hash window.
print(json.dumps(ti, sort_keys=True, separators=(",", ":")))
' 2>/dev/null)"
  TOOL_NAME="$(printf '%s' "$PARSED" | sed -n '1p')"
  SESSION_ID="$(printf '%s' "$PARSED" | sed -n '2p')"
  CANONICAL_KEYS="$(printf '%s' "$PARSED" | sed -n '3,$p')"
elif command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "default"')"
  CANONICAL_KEYS="$(printf '%s' "$INPUT" | jq -cS '.tool_input // {}' 2>/dev/null || echo '{}')"
else
  exit 0
fi

# Bypass-token check.
if [ -n "${LOOP_BREAKER_BYPASS_TOKEN:-}" ] && [ -f "$LCB_TOKEN_SHA" ]; then
  EXPECTED="$(tr -d '[:space:]' < "$LCB_TOKEN_SHA" 2>/dev/null || echo)"
  if [ -n "$EXPECTED" ] && [ "$LOOP_BREAKER_BYPASS_TOKEN" = "$EXPECTED" ]; then
    printf '[loop-cb-bypass] tool=%s session=%s\n' "$TOOL_NAME" "$SESSION_ID" >&2
    printf '{"event":"loop-circuit-breaker","ts":"%s","counter":"bypass","value":0,"ceiling":0,"action":"bypass","session_id":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${SESSION_ID//\"/}" >> "$TELEM_FILE" 2>/dev/null || true
    exit 0
  fi
fi

CSESS_DIR="$HOME_DIR/.claude/sessions/$SESSION_ID"
COUNTERS_FILE="$CSESS_DIR/counters.json"
[ -d "$CSESS_DIR" ] || mkdir -p "$CSESS_DIR" 2>/dev/null || exit 0

# Read counters via python3 (jq lacks easy windowing); fall back to jq.
COUNTERS_JSON=""
if [ -f "$COUNTERS_FILE" ]; then
  COUNTERS_JSON="$(cat "$COUNTERS_FILE" 2>/dev/null || echo)"
fi
[ -z "$COUNTERS_JSON" ] && COUNTERS_JSON='{}'

# Compute canonical hash.
CANONICAL="$TOOL_NAME|$CANONICAL_KEYS"
if command -v sha256sum >/dev/null 2>&1; then
  THIS_HASH="$(printf '%s' "$CANONICAL" | sha256sum | cut -c1-16)"
elif command -v shasum >/dev/null 2>&1; then
  THIS_HASH="$(printf '%s' "$CANONICAL" | shasum -a 256 | cut -c1-16)"
else
  THIS_HASH="$(printf '%s' "$CANONICAL" | head -c 16)"
fi

# Update counters via python (pass JSON over stdin to avoid shell quoting).
UPDATED="$(printf '%s' "$COUNTERS_JSON" | LCB_THIS_HASH="$THIS_HASH" LCB_SESSION_ID="$SESSION_ID" LCB_ITER_CEILING="$ITER_CEILING" LCB_USD_CEILING="$USD_CEILING" python3 -c '
import json, os, sys
try:
    c = json.load(sys.stdin)
    if not isinstance(c, dict): c = {}
except Exception:
    c = {}
iter_count = int(c.get("iteration_count", 0) or 0) + 1
iter_ceiling = int(c.get("iteration_ceiling", 0) or 0) or int(os.environ.get("LCB_ITER_CEILING", "150"))
usd_spent = float(c.get("usd_spent", 0) or 0)
usd_ceiling = float(c.get("usd_ceiling", 0) or 0) or float(os.environ.get("LCB_USD_CEILING", "25.0"))
window = c.get("hash_window") or []
if not isinstance(window, list): window = []
this_hash = os.environ.get("LCB_THIS_HASH", "")
window.append(this_hash)
window = window[-10:]
collisions = sum(1 for h in window if h == this_hash)
out = {
  "iteration_count": iter_count,
  "iteration_ceiling": iter_ceiling,
  "usd_spent": usd_spent,
  "usd_ceiling": usd_ceiling,
  "hash_window": window,
  "hash_collisions": collisions,
  "session_id": os.environ.get("LCB_SESSION_ID", ""),
  "started_at": int(c.get("started_at", 0) or 0)
}
print(json.dumps(out))
' 2>/dev/null)"

[ -z "$UPDATED" ] && exit 0
printf '%s\n' "$UPDATED" > "$COUNTERS_FILE" 2>/dev/null || true

# Extract values for halting decision.
ITER="$(printf '%s' "$UPDATED" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("iteration_count",0))')"
USD="$(printf '%s' "$UPDATED" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("usd_spent",0))')"
COLL="$(printf '%s' "$UPDATED" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("hash_collisions",0))')"

emit_telemetry() {
  local counter="$1" value="$2" ceiling="$3" action="$4"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"event":"loop-circuit-breaker","ts":"%s","counter":"%s","value":%s,"ceiling":%s,"action":"%s","session_id":"%s"}\n' \
    "$ts" "$counter" "$value" "$ceiling" "$action" "${SESSION_ID//\"/}" \
    >> "$TELEM_FILE" 2>/dev/null || true
}

# Precedence: iteration → usd → collisions.
if [ "$ITER" -gt "$ITER_CEILING" ]; then
  emit_telemetry "iteration_count" "$ITER" "$ITER_CEILING" "halt"
  printf '[LOOP-CIRCUIT-BREAKER] halted: counter=iteration_count value=%s ceiling=%s\n' "$ITER" "$ITER_CEILING" >&2
  exit 2
fi

# USD comparison via awk (float).
if awk -v u="$USD" -v c="$USD_CEILING" 'BEGIN{exit !(u+0 > c+0)}'; then
  emit_telemetry "usd_spent" "$USD" "$USD_CEILING" "halt"
  printf '[LOOP-CIRCUIT-BREAKER] halted: counter=usd_spent value=%s ceiling=%s\n' "$USD" "$USD_CEILING" >&2
  exit 2
fi

if [ "${COLL:-0}" -ge 3 ]; then
  emit_telemetry "hash_collisions" "$COLL" "3" "halt"
  printf '[LOOP-CIRCUIT-BREAKER] halted: counter=hash_collisions value=%s ceiling=3\n' "$COLL" >&2
  exit 2
fi

emit_telemetry "iteration_count" "$ITER" "$ITER_CEILING" "increment"
exit 0
