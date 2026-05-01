#!/usr/bin/env bash
# test-infer-audit-id.sh — unit test for AUDIT-003.
#
# AUDIT-003 root cause: the previous implementation of infer_audit_id picked
# the alphabetically-first spec basename. With ≥2 specs in docs/sdlc/spec/,
# every operator got the same id regardless of which feature they were
# working on, and the gate read the wrong findings file.
#
# Fix (AUDIT-003 recommended_fix precedence):
#   1. $AUDIT_ID env override (regex-validated)
#   2. branch `<prefix>/<slug>` matching docs/sdlc/spec/<slug>.md
#   3. single matching spec basename
#   4. multi-spec → title disambiguation against branch slug
#   5. fallback: <slug>-<short-sha> or audit-<short-sha>

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../hooks/_lib-audit-classify.sh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q .
git -c user.email=t@t -c user.name=t commit --allow-empty -q -m 'init'
mkdir -p docs/sdlc/spec
echo "# spec a" > docs/sdlc/spec/spec-a.md
echo "# spec b" > docs/sdlc/spec/spec-b.md
echo "# spec c" > docs/sdlc/spec/spec-c.md

# shellcheck disable=SC1090
. "$LIB"

PASS=0
FAIL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS [$name]: $actual"
    PASS=$((PASS+1))
  else
    echo "FAIL [$name]: expected '$expected', got '$actual'"
    FAIL=$((FAIL+1))
  fi
}

# Case 1: env var override wins regardless of specs/branch.
git checkout -q -b feat/spec-a
result="$(AUDIT_ID=spec-c infer_audit_id)"
assert_eq "env-override" "spec-c" "$result"

# Case 2: env var unset, branch `feat/spec-b` matches docs/sdlc/spec/spec-b.md.
git checkout -q -b feat/spec-b
unset AUDIT_ID
result="$(infer_audit_id)"
assert_eq "branch-matches-spec" "spec-b" "$result"

# Case 3: branch matches no spec → falls back to <slug>-<sha>.
git checkout -q -b feat/no-such-spec
result="$(infer_audit_id)"
sha="$(git rev-parse --short=8 HEAD)"
assert_eq "fallback-slug-sha" "no-such-spec-${sha}" "$result"

# Case 4 (regression for AUDIT-003): multiple specs, branch matches none
# → MUST NOT silently return alphabetically-first basename. Falls back to
# slug-sha because matches > 1 and no title match.
result="$(infer_audit_id)"
[ "$result" != "spec-a" ] && [ "$result" != "spec-b" ] && [ "$result" != "spec-c" ]
if [ $? -eq 0 ]; then
  echo "PASS [no-silent-alphabetic-pick]: $result"
  PASS=$((PASS+1))
else
  echo "FAIL [no-silent-alphabetic-pick]: returned a spec basename despite ambiguity: $result"
  FAIL=$((FAIL+1))
fi

# Case 5: single-spec workspace — still works.
rm docs/sdlc/spec/spec-b.md docs/sdlc/spec/spec-c.md
git checkout -q -b feat/random
result="$(infer_audit_id)"
assert_eq "single-spec" "spec-a" "$result"

# Case 6: env var with bad pattern is rejected (falls through to next rule).
git checkout -q feat/spec-a 2>/dev/null || git checkout -q -b feat/spec-a
result="$(AUDIT_ID='Bad Id With Spaces' infer_audit_id)"
assert_eq "bad-env-rejected" "spec-a" "$result"

echo "---"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
