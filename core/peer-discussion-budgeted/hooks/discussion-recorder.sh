#!/usr/bin/env bash
# discussion-recorder.sh — PostToolUse(mcp__claude-peers__send_message
# | mcp__claude-peers__check_messages).
#
# Auto-appends every tagged peer-discussion message to the per-topic
# record file at $CLAUDE_PROJECT_DIR/audits/discussions/<slug>.md.
#
# Idempotent — same (ts, from, to, content_hash) tuple is only recorded
# once. Untagged messages are skipped.
#
# Forbidden content (TM4): no LLM-spawn literals.
# Origin: docs/decisions/2026-05-04-live-discussion-skill.md.

set -uo pipefail

case "${PEER_DISCUSSION_BUDGETED_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

HOME_DIR="${HOME:-/root}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
RECORD_DIR="$PROJECT_DIR/audits/discussions"
LEDGER="$PROJECT_DIR/audits/VERIFICATION-LEDGER.md"
WAVE_ID="${CLAUDE_WAVE_ID:-unknown}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"

# Parse tool_name + payload. The exact shape depends on which MCP
# call fired; both send_message and check_messages can carry tagged
# content. We extract:
#   - For send_message: tool_input.{to, message}, tool_response.success?
#     plus self-identity (from = "me" → use $SESSION_ID short).
#   - For check_messages: tool_response is array of {from, message, ts}.
TOOL_NAME=""
SESSION_ID="default"
if command -v python3 >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
print(d.get("tool_name", "") or "")
' 2>/dev/null)"
  SESSION_ID="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: print("default"); sys.exit(0)
print(d.get("session_id", "") or "default")
' 2>/dev/null)"
elif command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "default"')"
fi

case "$TOOL_NAME" in
  mcp__claude-peers__send_message|mcp__claude-peers__check_messages) ;;
  *) exit 0 ;;
esac

# Build the records to append: list of {from, to, ts, subject, body, slug}.
# The python helper handles both shapes.
RECORDS_JSON="$(
  PD_TOOL="$TOOL_NAME" \
  PD_SESSION="$SESSION_ID" \
  python3 -c '
import json, os, sys, time, hashlib

tool = os.environ.get("PD_TOOL", "")
session = os.environ.get("PD_SESSION", "default")
short_session = session[:8] if session else "anon"

try:
    raw = sys.stdin.read()
    d = json.loads(raw)
except Exception:
    print("[]")
    sys.exit(0)

ti = d.get("tool_input") or {}
tr = d.get("tool_response") or d.get("tool_result") or {}
records = []

def parse_message(msg, from_id, to_id):
    if not msg or not isinstance(msg, str):
        return None
    first_line = msg.split("\n", 1)[0]
    import re
    m = re.match(r"^\[discussion:\s*([a-z0-9][a-z0-9-]{2,63})\]\s*(.*)$", first_line)
    if not m:
        return None
    slug = m.group(1)
    subject = m.group(2).strip() or "(no subject)"
    body = msg.split("\n", 1)[1] if "\n" in msg else ""
    body = body.lstrip("\n")
    h = hashlib.sha256(((from_id or "") + "|" + (to_id or "") + "|" + msg).encode()).hexdigest()[:12]
    return {
        "slug": slug,
        "subject": subject,
        "body": body,
        "from": from_id or "self",
        "to": to_id or "peer",
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "hash": h,
    }

if tool == "mcp__claude-peers__send_message":
    msg = ti.get("message", "")
    to = ti.get("to", "peer")
    rec = parse_message(msg, short_session, to)
    if rec: records.append(rec)
elif tool == "mcp__claude-peers__check_messages":
    msgs = tr if isinstance(tr, list) else (tr.get("messages") if isinstance(tr, dict) else None)
    if isinstance(msgs, list):
        for m in msgs:
            if not isinstance(m, dict): continue
            rec = parse_message(m.get("message", "") or m.get("content", ""),
                                m.get("from") or m.get("from_id"),
                                short_session)
            if rec: records.append(rec)

print(json.dumps(records))
' <<< "$INPUT" 2>/dev/null
)"

[ -n "$RECORDS_JSON" ] || exit 0
[ "$RECORDS_JSON" = "[]" ] && exit 0

mkdir -p "$RECORD_DIR" 2>/dev/null || exit 0

# Iterate records via python and write to disk.
PD_RECORD_DIR="$RECORD_DIR" \
PD_LEDGER="$LEDGER" \
PD_WAVE="$WAVE_ID" \
PD_TELEM="$TELEM_FILE" \
PD_RECORDS="$RECORDS_JSON" \
python3 -c '
import json, os, hashlib, time, sys

records = json.loads(os.environ.get("PD_RECORDS", "[]"))
record_dir = os.environ.get("PD_RECORD_DIR", "")
ledger = os.environ.get("PD_LEDGER", "")
wave = os.environ.get("PD_WAVE", "unknown")
telem = os.environ.get("PD_TELEM", "")

for rec in records:
    slug = rec["slug"]
    fpath = os.path.join(record_dir, f"{slug}.md")
    is_new = not os.path.exists(fpath)
    # Idempotency: skip if hash already in file.
    if not is_new:
        try:
            with open(fpath, "r") as f:
                if f"hash:{rec[\"hash\"]}" in f.read():
                    continue
        except Exception:
            pass
    # Compose block.
    block = []
    if is_new:
        block.append(f"# Discussion: {slug}\n")
        block.append(f"Started: {rec[\"ts\"]}  ·  Wave: {wave}\n")
        block.append("Convention: peer-discussion-budgeted v1.9\n\n---\n\n")
    block.append(f"## {rec[\"ts\"]} — {rec[\"from\"]} → {rec[\"to\"]}\n\n")
    block.append(f"> Subject: {rec[\"subject\"]}\n\n")
    if rec["body"].strip():
        block.append(f"{rec[\"body\"]}\n\n")
    block.append(f"<!-- hash:{rec[\"hash\"]} -->\n\n---\n\n")
    try:
        with open(fpath, "a") as f:
            f.write("".join(block))
    except Exception:
        continue
    # Ledger append on first message of topic.
    if is_new and ledger and os.path.exists(os.path.dirname(ledger)):
        try:
            with open(ledger, "a") as lf:
                lf.write(f"- [discussion] {slug} opened {rec[\"ts\"]} by {rec[\"from\"]} → see audits/discussions/{slug}.md\n")
        except Exception:
            pass
    # Telemetry.
    if telem:
        try:
            with open(telem, "a") as tf:
                tf.write(json.dumps({
                    "event": "peer-discussion-budgeted",
                    "action": "recorded",
                    "topic": slug,
                    "message_hash": rec["hash"],
                    "ts": rec["ts"],
                }) + "\n")
        except Exception:
            pass
' 2>/dev/null

exit 0
