#!/usr/bin/env bash
# test-high-entropy-fp.sh — regression test for Finding-S4-1.
#
# A 40+ char lowercase-hex string in a `commit <sha>` context (or as a
# bare git commit SHA, file digest, etc.) MUST NOT trip the gate. The
# `high_entropy_hex` regex is demoted to `mode: telemetry` so the signal
# is still recorded in ~/.claude/telemetry.jsonl with
# decision="telemetry-match", but the hook exits 0 (pass).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
HOOK="$REPO_ROOT/core/hardcoded-credential-refusal/hooks/credential-scan.sh"
TPL="$REPO_ROOT/core/hardcoded-credential-refusal/templates/credential-regex-bank.txt"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export HARDCODED_CREDENTIAL_REFUSAL_DIR="$TMP/.claude/hardcoded-credential-refusal"
export HARDCODED_CREDENTIAL_REFUSAL_BANK="$HARDCODED_CREDENTIAL_REFUSAL_DIR/credential-regex-bank.txt"
export GOVERNANCE_PACK_TELEMETRY_FILE="$TMP/.claude/telemetry.jsonl"
mkdir -p "$HARDCODED_CREDENTIAL_REFUSAL_DIR" "$TMP/.claude"
cp "$TPL" "$HARDCODED_CREDENTIAL_REFUSAL_BANK"

fail=0

run_case() {
  local name="$1" body="$2" expect_exit="$3"
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({
    "tool_name": "Edit",
    "session_id": "fp-regression",
    "tool_input": {"file_path": "/tmp/x.md", "old_string": "a", "new_string": sys.argv[1]},
}))
' "$body")
  local out exit_code
  out="$(printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)"
  exit_code=$?
  if [ "$exit_code" -ne "$expect_exit" ]; then
    printf 'FAIL: case=%s expected=%s got=%s stderr=%s\n' \
      "$name" "$expect_exit" "$exit_code" "$out" >&2
    fail=1
    return
  fi
  printf 'PASS: case=%s exit=%s\n' "$name" "$exit_code"
}

# 1. Bare 40-hex (git commit SHA) → pass (telemetry-only)
run_case "bare-sha"     "see commit a4f2c1d9aaa3bbf2c4d9aaa3bbf2c4d9aaa3bbf2 for context" 0
# 2. `commit <sha>` line in a CHANGELOG-style edit → pass
run_case "commit-line"  "commit deadbeefcafebabe1234567890abcdef1234567890 fix: foo" 0
# 3. SHA-1 file digest line → pass
run_case "sha-prefix"   "sha: 0123456789abcdef0123456789abcdef01234567"        0
# 4. Real AWS key co-occurring with hex → still refuses (other regex catches it)
# AWS-key fixture assembled at runtime to dodge GitHub Push Protection on this
# test file (the local hook still scans the assembled string).
_AWS=$(printf '%s' "AKI" "AABCDEFGHIJKLMNOP")
run_case "aws-still-refused" "k=\"${_AWS}\"; sha=a4f2c1d9aaa3bbf2c4d9aaa3bbf2c4d9aaa3bbf2" 2

# Verify telemetry recorded a `telemetry-match` line for the bare-sha case.
if grep -q '"decision":"telemetry-match"' "$GOVERNANCE_PACK_TELEMETRY_FILE" 2>/dev/null; then
  printf 'PASS: telemetry recorded `telemetry-match` line\n'
else
  printf 'FAIL: no `telemetry-match` line in %s\n' "$GOVERNANCE_PACK_TELEMETRY_FILE" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-high-entropy-fp: PASS (4/4 + telemetry)\n'
fi
exit "$fail"
