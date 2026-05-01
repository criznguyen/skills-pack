#!/usr/bin/env bash
# test-flag.sh — smoke-test install-flag against a tmp HOME.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
FLAG="$REPO_ROOT/core/sandbox-default-on/install-flag.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export GOVERNANCE_PACK_TELEMETRY_FILE="$TMP/.claude/telemetry.jsonl"
mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "defaultMode": "default",
    "deny": []
  }
}
JSON

fail=0

# 1. Missing settings.json → exit 1.
rm "$TMP/.claude/settings.json"
ec=0
bash "$FLAG" >/dev/null 2>&1 || ec=$?
if [ "$ec" -ne 1 ]; then
  printf 'FAIL: missing settings.json should exit 1; got %s\n' "$ec" >&2
  fail=1
else
  printf 'PASS: missing settings.json → exit 1\n'
fi

# Restore.
cat > "$TMP/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "defaultMode": "default"
  }
}
JSON

# 2. First flip → enabled.
ec=0
out=$(bash "$FLAG" 2>&1) || ec=$?
mode=$(jq -r '.permissions.defaultMode' "$TMP/.claude/settings.json")
if [ "$ec" -eq 0 ] && [ "$mode" = "sandbox" ] && printf '%s' "$out" | grep -q 'enabled'; then
  printf 'PASS: first flip → mode=sandbox\n'
else
  printf 'FAIL: first flip — ec=%s mode=%s out=%s\n' "$ec" "$mode" "$out" >&2
  fail=1
fi

# 3. Second flip → already-set.
ec=0
out=$(bash "$FLAG" 2>&1) || ec=$?
mode=$(jq -r '.permissions.defaultMode' "$TMP/.claude/settings.json")
if [ "$ec" -eq 0 ] && [ "$mode" = "sandbox" ] && printf '%s' "$out" | grep -q 'already-set'; then
  printf 'PASS: second flip → already-set\n'
else
  printf 'FAIL: second flip — ec=%s mode=%s out=%s\n' "$ec" "$mode" "$out" >&2
  fail=1
fi

# 4. Telemetry has 2 lines (enabled + already-set).
T="$GOVERNANCE_PACK_TELEMETRY_FILE"
if [ -f "$T" ]; then
  COUNT=$(grep -c '"event":"sandbox-default-on"' "$T")
  if [ "$COUNT" -ge 2 ]; then
    printf 'PASS: telemetry recorded %s entries\n' "$COUNT"
  else
    printf 'FAIL: telemetry expected ≥2 entries; got %s\n' "$COUNT" >&2
    fail=1
  fi
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-flag: PASS\n'
fi
exit "$fail"
