#!/usr/bin/env bash
# test-credential-scan.sh — 9-case unit suite.

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
  local name="$1" tool="$2" body_field="$3" body="$4" expect_exit="$5"
  local payload
  payload=$(python3 -c '
import json, sys
tool, field, body = sys.argv[1], sys.argv[2], sys.argv[3]
ti = {"file_path":"/tmp/x.js"}
if tool == "MultiEdit":
    ti["edits"] = [{"old_string":"a", "new_string": body}]
else:
    ti[field] = body
print(json.dumps({"tool_name": tool, "session_id": "t", "tool_input": ti}))
' "$tool" "$body_field" "$body")
  local out exit_code
  out="$(printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)"
  exit_code=$?
  if [ "$exit_code" -ne "$expect_exit" ]; then
    printf 'FAIL: case=%s expected exit=%s got=%s stderr=%s\n' "$name" "$expect_exit" "$exit_code" "$out" >&2
    fail=1
    return
  fi
  printf 'PASS: case=%s exit=%s\n' "$name" "$exit_code"
}

# Fake-credential fixtures are assembled at runtime so the source file does
# not contain the literal regex-matching tokens — this dodges GitHub Push
# Protection and gitleaks pre-receive hooks on the test file itself. The
# runtime payloads still match the local regex bank — that is the test.
_j() { printf '%s' "$@"; }
AWS_KEY1=$(_j "AKI"   "AABCDEFGHIJKLMNOP")
AWS_KEY2=$(_j "AKI"   "AQRSTUVWXYZ012345")
AWS_DOC=$( _j "AKI"   "AIOSFODNN7EXAMPLE")
GH_PAT=$(  _j "gh"    "p_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789")
STRIPE_KEY=$(_j "sk_" "live_abcdefghijklmnopqrstuvwx")
OPENAI_KEY=$(_j "sk"  "-abcdefghijABCDEFGHIJ0123456789ABCDEFGHIJabcd1234")
RSA_HDR=$( _j "-----BEGIN RSA " "PRIVATE KEY-----")

# 1. AWS access key → refuse
run_case "aws-key"          "Edit"  "new_string" "const k = \"${AWS_KEY1}\";"  2
# 2. GitHub PAT → refuse
run_case "github-pat"       "Edit"  "new_string" "const k = \"${GH_PAT}\";"  2
# 3. Stripe live → refuse
run_case "stripe-live"      "Write" "content"    "const k = \"${STRIPE_KEY}\";"  2
# 4. OpenAI key → refuse
run_case "openai-key"       "Edit"  "new_string" "const k = \"${OPENAI_KEY}\";"  2
# 5. RSA private → refuse
run_case "rsa-private"      "Write" "content"    "${RSA_HDR}\nMIIEowIBAAKCAQEA"  2
# 6. JWT → refuse
run_case "jwt"              "Edit"  "new_string" "const t = \"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOjF9.abcDEF\";"  2
# 7. AWS official example → pass (regex bank denylist on EXAMPLE excludes it)
run_case "aws-example-ok"   "Write" "content"    "const k = \"${AWS_DOC}\";"  0
# 8. gitleaks:allow marker bypass → pass
run_case "marker-bypass"    "Edit"  "new_string" "// gitleaks:allow — fixture\nconst k = \"${AWS_KEY1}\";"  0
# 9. MultiEdit with credential in nested edits[]
run_case "multiedit-aws"    "MultiEdit" "new_string" "const k = \"${AWS_KEY2}\";"  2
# 10. Innocent code → pass
run_case "innocent-ok"      "Write" "content"    "console.log('hello');"  0

if [ "$fail" -eq 0 ]; then
  printf 'test-credential-scan: PASS (10/10)\n'
fi
exit "$fail"
