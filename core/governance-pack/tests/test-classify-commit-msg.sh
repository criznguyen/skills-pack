#!/usr/bin/env bash
# test-classify-commit-msg.sh — regression test for AUDIT-001.
#
# AUDIT-001 root cause: the hook was registered as `pre-commit` and read
# `.git/COMMIT_EDITMSG`, which at pre-commit time holds the PREVIOUS commit's
# message (or is empty). Concretely:
#   commit 1: feat: first feature        → hook saw class=unknown
#   commit 2: chore: tiny chore          → hook saw class=feature (stale feat:)
#   commit 3: feat: real feature         → hook saw class=chore (stale chore:)
#                                          and SKIPPED — strict-mode BLOCK never fired.
#
# Fix: register as `commit-msg`; git passes the message-file path as $1.
#
# This test simulates 3 sequential commit-msg invocations and asserts each is
# classified correctly. It does NOT actually run `git commit` (avoids
# repository-state side effects); instead it mimics what git does — write the
# message to a file, then invoke the hook with that file path as $1.
#
# Exit 0 = all pass. Exit 1 = at least one mis-classification.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/commit-msg-audit-check.sh"
LIB_DIR="$SCRIPT_DIR/../hooks"

if [ ! -x "$HOOK" ]; then
  echo "FAIL: hook not executable at $HOOK"
  exit 1
fi

# Run in an isolated temp dir so the hook's cwd-relative checks (FINDINGS path)
# do not pick up the live repo's docs/sdlc/audit/ files.
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q .
mkdir -p docs/sdlc/spec
# Single spec → infer_audit_id returns 'classifier-test-only' deterministically
# in this isolated repo.
echo "# spec" > docs/sdlc/spec/classifier-test-only.md

PASS=0
FAIL=0

# run_case <case-name> <message> <expected-class>
run_case() {
  local name="$1" message="$2" expected="$3"
  local msg_file="$TMPDIR/.git/COMMIT_EDITMSG_$name"
  printf '%s\n' "$message" > "$msg_file"
  local stderr_file="$TMPDIR/stderr.$name"
  # Hook sources lib via SELF_DIR (sibling of $HOOK in source tree) — works
  # because we point to the repo's hooks/ directory directly.
  GOVERNANCE_PACK_HOOKS_DIR="$LIB_DIR" \
    "$HOOK" "$msg_file" 2>"$stderr_file" || true
  local out
  out="$(cat "$stderr_file")"
  if printf '%s' "$out" | grep -qE "class=${expected}\b"; then
    echo "PASS [$name]: class=${expected}"
    PASS=$((PASS+1))
  else
    echo "FAIL [$name]: expected class=${expected}, got: $out"
    FAIL=$((FAIL+1))
  fi
}

# Three sequential commits — the AUDIT-001 scenario from the findings JSON.
run_case "commit1-feat"  "feat: first feature"   "feature"
run_case "commit2-chore" "chore: tiny chore"     "chore"
run_case "commit3-feat"  "feat: real feature"    "feature"

echo "---"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
