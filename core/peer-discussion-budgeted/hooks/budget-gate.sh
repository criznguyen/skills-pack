#!/usr/bin/env bash
# budget-gate.sh — PreToolUse(mcp__claude-peers__send_message).
#
# Caps tagged peer-discussion threads at MAX_TOPICS_PER_SESSION distinct
# topics × MAX_ROUND_TRIPS_PER_TOPIC round-trips. Untagged peer messages
# (no `[discussion: <slug>]` first-line prefix) pass through unchanged.
#
# Refusal at exit 2 with stderr advisory; the agent is expected to read
# the existing discussion record and decide unilaterally OR surface a
# structured failure-report to the orchestrator. NO infinite-discussion
# tarpits.
#
# Counter file: ~/.claude/sessions/<session_id>/discussion-counters.json
# Schema:
#   {
#     "topics": {
#       "<slug>": { "round_trips": N, "first_seen_ts": "..." }
#     },
#     "topic_count": M
#   }
#
# Forbidden content (TM4): no LLM-spawn literals.
# Origin: docs/decisions/2026-05-04-live-discussion-skill.md (slim variant).

set -uo pipefail

case "${PEER_DISCUSSION_BUDGETED_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

HOME_DIR="${HOME:-/root}"
MAX_TOPICS="${PEER_DISCUSSION_MAX_TOPICS:-5}"
MAX_ROUND_TRIPS="${PEER_DISCUSSION_MAX_ROUND_TRIPS:-3}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null || true

# Parse tool_name + tool_input.message + session_id.
# Use jq first (single-value extraction is unambiguous), fall back to
# 3 separate python calls (still single-value each — no multi-line
# stitching that bash command-substitution trailing-newline strip would
# corrupt for single-line messages).
TOOL_NAME=""
MESSAGE=""
SESSION_ID="default"
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
  MESSAGE="$(printf '%s' "$INPUT" | jq -r '.tool_input.message // ""')"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "default"')"
elif command -v python3 >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except: print(""); sys.exit(0)
print(d.get("tool_name","") or "")' 2>/dev/null)"
  MESSAGE="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: d=json.load(sys.stdin); ti=d.get("tool_input") or {}
except: print(""); sys.exit(0)
if not isinstance(ti, dict): ti={}
print(ti.get("message","") or "")' 2>/dev/null)"
  SESSION_ID="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except: print("default"); sys.exit(0)
print(d.get("session_id","") or "default")' 2>/dev/null)"
else
  exit 0
fi

# Only fire on send_message of claude-peers MCP.
case "$TOOL_NAME" in
  mcp__claude-peers__send_message) ;;
  *) exit 0 ;;
esac
[ -n "$MESSAGE" ] || exit 0

# Extract topic slug from first line if pattern matches.
FIRST_LINE="$(printf '%s' "$MESSAGE" | head -n1)"
TOPIC_SLUG=""
if printf '%s' "$FIRST_LINE" | grep -qE '^\[discussion:[[:space:]]*[a-z0-9][a-z0-9-]{2,63}\]'; then
  TOPIC_SLUG="$(printf '%s' "$FIRST_LINE" | sed -nE 's/^\[discussion:[[:space:]]*([a-z0-9][a-z0-9-]{2,63})\].*/\1/p')"
fi

# No tag → casual peer message; pass through silently.
if [ -z "$TOPIC_SLUG" ]; then
  exit 0
fi

emit_telemetry() {
  local action="$1" topic="$2" rt="$3" tc="$4"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"event":"peer-discussion-budgeted","ts":"%s","action":"%s","topic":"%s","round_trips":%s,"topic_count":%s,"session_id":"%s"}\n' \
    "$ts" "$action" "$topic" "${rt:-0}" "${tc:-0}" "${SESSION_ID//\"/}" \
    >> "$TELEM_FILE" 2>/dev/null || true
}

CSESS_DIR="$HOME_DIR/.claude/sessions/$SESSION_ID"
COUNTER_FILE="$CSESS_DIR/discussion-counters.json"
[ -d "$CSESS_DIR" ] || mkdir -p "$CSESS_DIR" 2>/dev/null || exit 0

# Update counters via python.
UPDATED="$(
  PD_TOPIC="$TOPIC_SLUG" \
  PD_MAX_TOPICS="$MAX_TOPICS" \
  PD_MAX_RT="$MAX_ROUND_TRIPS" \
  PD_COUNTER_FILE="$COUNTER_FILE" \
  python3 -c '
import json, os, sys, time
cf = os.environ["PD_COUNTER_FILE"]
topic = os.environ["PD_TOPIC"]
max_topics = int(os.environ["PD_MAX_TOPICS"])
max_rt = int(os.environ["PD_MAX_RT"])
try:
    with open(cf, "r") as f: c = json.load(f)
    if not isinstance(c, dict): c = {}
except Exception:
    c = {}
topics = c.get("topics") or {}
if not isinstance(topics, dict): topics = {}
ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
existing = topics.get(topic)
status = ""
if existing:
    rt = int(existing.get("round_trips", 0) or 0) + 1
    if rt > max_rt:
        status = "halt-topic-cap"
        rt = int(existing.get("round_trips", 0) or 0)
    else:
        existing["round_trips"] = rt
        topics[topic] = existing
else:
    if len(topics) >= max_topics:
        status = "halt-session-cap"
    else:
        topics[topic] = {"round_trips": 1, "first_seen_ts": ts}
        status = "opened"
c["topics"] = topics
c["topic_count"] = len(topics)
if status not in ("halt-topic-cap", "halt-session-cap"):
    if not status:
        status = "round-trip"
    with open(cf, "w") as f: json.dump(c, f)
out = {"status": status, "round_trips": int((topics.get(topic) or {}).get("round_trips", 0) or 0), "topic_count": len(topics)}
print(json.dumps(out))
' 2>/dev/null
)"

[ -n "$UPDATED" ] || exit 0

STATUS="$(printf '%s' "$UPDATED" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
RT="$(printf '%s' "$UPDATED" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("round_trips",0))')"
TC="$(printf '%s' "$UPDATED" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("topic_count",0))')"

case "$STATUS" in
  halt-topic-cap)
    emit_telemetry "halt-topic-cap" "$TOPIC_SLUG" "$RT" "$TC"
    printf '[peer-discussion-budgeted] halted: topic=%s round_trips=%s ceiling=%s\n' \
      "$TOPIC_SLUG" "$RT" "$MAX_ROUND_TRIPS" >&2
    printf 'Read audits/discussions/%s.md and decide unilaterally OR surface a structured failure-report.\n' "$TOPIC_SLUG" >&2
    printf 'Bypass: PEER_DISCUSSION_BUDGETED_DISABLE=1 (not recommended).\n' >&2
    exit 2
    ;;
  halt-session-cap)
    emit_telemetry "halt-session-cap" "$TOPIC_SLUG" "$RT" "$TC"
    printf '[peer-discussion-budgeted] halted: new topic=%s would exceed session cap topic_count=%s ceiling=%s\n' \
      "$TOPIC_SLUG" "$TC" "$MAX_TOPICS" >&2
    printf 'Use plain peer messages (no [discussion:...] prefix) for further coordination, or close existing discussions first.\n' >&2
    exit 2
    ;;
  opened)
    emit_telemetry "opened" "$TOPIC_SLUG" "$RT" "$TC"
    ;;
  round-trip)
    emit_telemetry "round-trip" "$TOPIC_SLUG" "$RT" "$TC"
    ;;
esac

exit 0
