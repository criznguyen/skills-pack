#!/usr/bin/env bash
# Tests for budget-gate.sh
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$THIS_DIR/../hooks/budget-gate.sh"

PASS=0
FAIL=0
log() { printf '%s\n' "$*" >&2; }

# Use isolated HOME.
TMPHOME=$(mktemp -d)
export HOME="$TMPHOME"

SESSION="11111111-1111-1111-1111-111111111111"

mk_input() {
  local tool="$1" message="$2"
  local sess="${3:-$SESSION}"
  printf '{"tool_name":"%s","tool_input":{"to":"peer-x","message":"%s"},"session_id":"%s"}' \
    "$tool" "${message//\"/\\\"}" "$sess"
}

# Test 1: non-peer-message tool → no-op exit 0
RESULT="$(mk_input "Edit" "anything" | "$GATE"; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && PASS=$((PASS+1)) && log "PASS: t1 non-peer tool skips" || { FAIL=$((FAIL+1)); log "FAIL: t1 | $RESULT"; }

# Test 2: untagged peer message → no-op exit 0, no counter file change
rm -rf "$TMPHOME/.claude"
RESULT="$(mk_input "mcp__claude-peers__send_message" "hello casual chat" | "$GATE"; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && [ ! -f "$TMPHOME/.claude/sessions/$SESSION/discussion-counters.json" ] && PASS=$((PASS+1)) && log "PASS: t2 untagged skips + no counter" || { FAIL=$((FAIL+1)); log "FAIL: t2 | $RESULT"; }

# Test 3: tagged message first time → opened, exit 0
RESULT="$(mk_input "mcp__claude-peers__send_message" "[discussion: contract-a] need shape\nbody here" | "$GATE"; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && \
  [ -f "$TMPHOME/.claude/sessions/$SESSION/discussion-counters.json" ] && \
  grep -q '"contract-a"' "$TMPHOME/.claude/sessions/$SESSION/discussion-counters.json" && \
  PASS=$((PASS+1)) && log "PASS: t3 tagged opened + counter created" || { FAIL=$((FAIL+1)); log "FAIL: t3 | $RESULT"; cat "$TMPHOME/.claude/sessions/$SESSION/discussion-counters.json" 2>&1 >&2; }

# Test 4: 2nd, 3rd message same topic → round-trip 2, 3
mk_input "mcp__claude-peers__send_message" "[discussion: contract-a] reply 2" | "$GATE" > /dev/null 2>&1
mk_input "mcp__claude-peers__send_message" "[discussion: contract-a] reply 3" | "$GATE" > /dev/null 2>&1
RT="$(python3 -c 'import json; print(json.load(open("'$TMPHOME'/.claude/sessions/'$SESSION'/discussion-counters.json"))["topics"]["contract-a"]["round_trips"])')"
[ "$RT" = "3" ] && PASS=$((PASS+1)) && log "PASS: t4 round_trips=3 after 3 sends" || { FAIL=$((FAIL+1)); log "FAIL: t4 RT=$RT"; }

# Test 5: 4th message same topic → halt-topic-cap exit 2
RESULT="$(mk_input "mcp__claude-peers__send_message" "[discussion: contract-a] reply 4" | "$GATE" 2>&1; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=2" && echo "$RESULT" | grep -q "halt" && PASS=$((PASS+1)) && log "PASS: t5 4th RT halts" || { FAIL=$((FAIL+1)); log "FAIL: t5 | $RESULT"; }

# Test 6: 5 distinct new topics fit; 6th topic refused
rm -rf "$TMPHOME/.claude"
for i in 1 2 3 4 5; do
  mk_input "mcp__claude-peers__send_message" "[discussion: topic-$i] s" | "$GATE" > /dev/null 2>&1
done
TOPIC_COUNT="$(python3 -c 'import json; print(json.load(open("'$TMPHOME'/.claude/sessions/'$SESSION'/discussion-counters.json"))["topic_count"])')"
[ "$TOPIC_COUNT" = "5" ] && PASS=$((PASS+1)) && log "PASS: t6a topic_count=5" || { FAIL=$((FAIL+1)); log "FAIL: t6a TC=$TOPIC_COUNT"; }
RESULT="$(mk_input "mcp__claude-peers__send_message" "[discussion: topic-6] s" | "$GATE" 2>&1; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=2" && echo "$RESULT" | grep -q "session cap" && PASS=$((PASS+1)) && log "PASS: t6b 6th topic halts" || { FAIL=$((FAIL+1)); log "FAIL: t6b | $RESULT"; }

# Test 7: env override raises caps
rm -rf "$TMPHOME/.claude"
RESULT="$(PEER_DISCUSSION_MAX_TOPICS=10 mk_input "mcp__claude-peers__send_message" "[discussion: topic-1] s" | PEER_DISCUSSION_MAX_TOPICS=10 "$GATE"; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && PASS=$((PASS+1)) && log "PASS: t7 env override applies" || { FAIL=$((FAIL+1)); log "FAIL: t7 | $RESULT"; }

# Test 8: DISABLE bypasses
RESULT="$(PEER_DISCUSSION_BUDGETED_DISABLE=1 mk_input "mcp__claude-peers__send_message" "[discussion: x] s" | PEER_DISCUSSION_BUDGETED_DISABLE=1 "$GATE"; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && PASS=$((PASS+1)) && log "PASS: t8 DISABLE bypasses" || { FAIL=$((FAIL+1)); log "FAIL: t8 | $RESULT"; }

# Test 9: invalid slug pattern (uppercase) → treated as untagged, no counter
rm -rf "$TMPHOME/.claude"
RESULT="$(mk_input "mcp__claude-peers__send_message" "[discussion: BadSlug] s" | "$GATE"; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && [ ! -f "$TMPHOME/.claude/sessions/$SESSION/discussion-counters.json" ] && PASS=$((PASS+1)) && log "PASS: t9 invalid slug → untagged" || { FAIL=$((FAIL+1)); log "FAIL: t9 | $RESULT"; }

rm -rf "$TMPHOME"

log ""
log "Results: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
