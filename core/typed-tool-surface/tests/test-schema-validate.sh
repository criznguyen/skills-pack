#!/usr/bin/env bash
# test-schema-validate.sh — pass / fail / skip cases.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
HOOK="$REPO_ROOT/core/typed-tool-surface/hooks/schema-validate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export GOVERNANCE_PACK_TELEMETRY_FILE="$TMP/.claude/telemetry.jsonl"
export TYPED_TOOL_SURFACE_CONF="$TMP/.claude/typed-tool-surface.json"
mkdir -p "$TMP/.claude"

SESSION="t-tts"
CACHE_DIR="$TMP/.claude/sessions/$SESSION"
mkdir -p "$CACHE_DIR"
cat > "$CACHE_DIR/skill-schemas.json" <<'JSON'
{
  "demo-skill": {
    "type": "object",
    "required": ["query"],
    "properties": {
      "query": { "type": "string" },
      "limit": { "type": "integer" }
    },
    "additionalProperties": false
  }
}
JSON

fail=0

run_case() {
  local name="$1" payload="$2" expect_decision="$3" expect_exit="$4"
  rm -f "$GOVERNANCE_PACK_TELEMETRY_FILE"
  local stderr_out exit_code
  stderr_out="$(printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)"
  exit_code=$?
  local decision
  decision="$(grep -o '"decision":"[^"]*"' "$GOVERNANCE_PACK_TELEMETRY_FILE" 2>/dev/null | tail -n1 | sed 's/.*:"\(.*\)"/\1/')"
  if [ "$exit_code" -ne "$expect_exit" ] || [ "$decision" != "$expect_decision" ]; then
    printf 'FAIL: case=%s expect=(decision=%s exit=%s) got=(decision=%s exit=%s) stderr=%s\n' \
      "$name" "$expect_decision" "$expect_exit" "$decision" "$exit_code" "$stderr_out" >&2
    fail=1
    return
  fi
  printf 'PASS: case=%s decision=%s exit=%s\n' "$name" "$decision" "$exit_code"
}

# 1. Pass: skill demo-skill, valid input.
run_case "pass-valid" \
  "$(printf '{"tool_name":"Demo","session_id":"%s","skill":"demo-skill","tool_input":{"query":"foo","limit":10}}' "$SESSION")" \
  "pass" 0

# 2. Fail: missing required `query`.
run_case "fail-missing-required" \
  "$(printf '{"tool_name":"Demo","session_id":"%s","skill":"demo-skill","tool_input":{"limit":10}}' "$SESSION")" \
  "fail" 0

# 3. Fail: wrong type.
run_case "fail-wrong-type" \
  "$(printf '{"tool_name":"Demo","session_id":"%s","skill":"demo-skill","tool_input":{"query":"foo","limit":"ten"}}' "$SESSION")" \
  "fail" 0

# 4. Fail: additional property forbidden.
run_case "fail-extra-prop" \
  "$(printf '{"tool_name":"Demo","session_id":"%s","skill":"demo-skill","tool_input":{"query":"foo","extra":1}}' "$SESSION")" \
  "fail" 0

# 5. Skip: no skill declared.
run_case "skip-no-skill" \
  "$(printf '{"tool_name":"Demo","session_id":"%s","tool_input":{"query":"foo"}}' "$SESSION")" \
  "skip" 0

# 6. Skip: skill present but no schema for it.
run_case "skip-no-schema" \
  "$(printf '{"tool_name":"Demo","session_id":"%s","skill":"unknown-skill","tool_input":{}}' "$SESSION")" \
  "skip" 0

# 7. Strict mode: missing schema → fail exit 2.
echo '{"mode":"strict"}' > "$TYPED_TOOL_SURFACE_CONF"
run_case "strict-no-schema" \
  "$(printf '{"tool_name":"Demo","session_id":"%s","skill":"unknown-skill","tool_input":{}}' "$SESSION")" \
  "fail" 2
rm -f "$TYPED_TOOL_SURFACE_CONF"

if [ "$fail" -eq 0 ]; then
  printf 'test-schema-validate: PASS (7/7)\n'
fi
exit "$fail"
