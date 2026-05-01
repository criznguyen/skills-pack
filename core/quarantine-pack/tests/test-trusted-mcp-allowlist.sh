#!/usr/bin/env bash
# test-trusted-mcp-allowlist.sh — unit tests for _lib-trusted-mcp.sh.
# Six cases per tech-spec §1.9. Exits non-zero on any failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
LIB="$REPO_ROOT/core/quarantine-pack/hooks/_lib-trusted-mcp.sh"
DEFAULT_ALLOWLIST="$REPO_ROOT/core/quarantine-pack/templates/trusted-mcp-allowlist.txt"

# shellcheck disable=SC1090
. "$LIB"

PASS=0
FAIL=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAIL=$((FAIL + 1))
}
pass() {
  PASS=$((PASS + 1))
}

# Case 1: trusted MCP returns 0 against default allowlist.
if is_trusted_mcp "mcp__linear_list_issues" "$DEFAULT_ALLOWLIST"; then
  pass
else
  fail "case 1: mcp__linear_list_issues should be trusted (RC=0)"
fi

# Case 2: untrusted MCP returns 1.
if is_trusted_mcp "mcp__zendesk_list_tickets" "$DEFAULT_ALLOWLIST"; then
  fail "case 2: mcp__zendesk_list_tickets should NOT be trusted (RC=1)"
else
  pass
fi

# Case 3: matched_trusted_namespace returns matched prefix.
got="$(matched_trusted_namespace "mcp__github_create_pr" "$DEFAULT_ALLOWLIST")"
if [ "$got" = "mcp__github" ]; then
  pass
else
  fail "case 3: matched_trusted_namespace mcp__github_create_pr → '$got' (expected mcp__github)"
fi

# Case 4: comment + blank lines ignored.
TMP="$(mktemp)"
{
  printf '# A leading comment\n'
  printf '\n'
  printf 'mcp__custom\n'
  printf '   # indented comment ignored only when first non-space char is # — bash case ignores this distinction\n'
} > "$TMP"
if is_trusted_mcp "mcp__custom_thing" "$TMP"; then
  pass
else
  fail "case 4: comment + blank lines should not break match for mcp__custom"
fi
rm -f "$TMP"

# Case 5: missing file → fail-closed (RC=1).
if is_trusted_mcp "mcp__anything" "/tmp/nonexistent-quarantine-allowlist-$$"; then
  fail "case 5: missing allowlist must NOT silently trust everything (TM7)"
else
  pass
fi

# Case 6: whitespace after namespace tolerated.
TMP="$(mktemp)"
printf 'mcp__linear   # internal ticket store\n' > "$TMP"
if is_trusted_mcp "mcp__linear_list_issues" "$TMP"; then
  pass
else
  fail "case 6: whitespace + inline comment after namespace should still match"
fi
rm -f "$TMP"

printf 'test-trusted-mcp-allowlist: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
