#!/usr/bin/env bash
# test-git-push-gate.sh — 8-case unit suite.
# allow/refuse/bypass × force-push / --no-verify × protected/unprotected.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
HOOK="$REPO_ROOT/core/git-force-push-gate/hooks/git-push-gate.sh"
TPL="$REPO_ROOT/core/git-force-push-gate/templates/protected-branches.txt"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a tmp git repo so `git symbolic-ref` returns something predictable.
WORK="$TMP/work"
mkdir -p "$WORK"
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t && \
  git commit -q --allow-empty -m init && git checkout -q -b main 2>/dev/null || true )

export HOME="$TMP"
export GIT_FORCE_PUSH_GATE_DIR="$TMP/.claude/git-force-push-gate"
export GIT_FORCE_PUSH_GATE_PROTECTED="$GIT_FORCE_PUSH_GATE_DIR/protected-branches.txt"
export GIT_FORCE_PUSH_GATE_ALLOW_DIR="$TMP/.claude/git-force-push-gate-allow"
export GIT_FORCE_PUSH_GATE_TOKEN_SHA="$GIT_FORCE_PUSH_GATE_DIR/bypass-token.sha"
export GOVERNANCE_PACK_TELEMETRY_FILE="$TMP/.claude/telemetry.jsonl"
mkdir -p "$GIT_FORCE_PUSH_GATE_DIR" "$GIT_FORCE_PUSH_GATE_ALLOW_DIR" "$TMP/.claude"
cp "$TPL" "$GIT_FORCE_PUSH_GATE_PROTECTED"

fail=0

run_case() {
  local name="$1" cmd="$2" cwd="$3" expect_exit="$4" expect_stderr_substr="$5"
  local payload
  payload=$(printf '{"tool_name":"Bash","session_id":"t","tool_input":{"command":%s,"cwd":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    "$(printf '%s' "$cwd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  local stderr_out exit_code
  stderr_out="$(printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)"
  exit_code=$?
  if [ "$exit_code" -ne "$expect_exit" ]; then
    printf 'FAIL: case=%s expected exit=%s; got=%s; stderr=%s\n' "$name" "$expect_exit" "$exit_code" "$stderr_out" >&2
    fail=1
    return
  fi
  if [ -n "$expect_stderr_substr" ]; then
    if ! printf '%s' "$stderr_out" | grep -q "$expect_stderr_substr"; then
      printf 'FAIL: case=%s expected stderr~%s; got=%s\n' "$name" "$expect_stderr_substr" "$stderr_out" >&2
      fail=1
      return
    fi
  fi
  printf 'PASS: case=%s exit=%s\n' "$name" "$exit_code"
}

# 1. force-push to main → refuse
run_case "force-push-main"           "git push --force origin main" "$WORK" 2 "git-push-gate-refused"

# 2. force-with-lease to main → refuse
run_case "force-with-lease-main"     "git push --force-with-lease origin main" "$WORK" 2 "git-push-gate-refused"

# 3. force-push to feature branch → allow
( cd "$WORK" && git checkout -q -b feat/personal 2>/dev/null )
run_case "force-push-feature"        "git push --force origin feat/personal" "$WORK" 0 "git-push-gate-allowed"

# 4. plain push to main → allow (no force, no no-verify)
( cd "$WORK" && git checkout -q main )
run_case "plain-push-main"           "git push origin main" "$WORK" 0 ""

# 5. --no-verify on commit → refuse (any branch)
run_case "commit-no-verify-feat"     "git commit --no-verify -m foo" "$WORK" 2 "git-push-gate-refused"

# 6. --no-verify on push → refuse
run_case "push-no-verify-main"       "git push --no-verify origin main" "$WORK" 2 "git-push-gate-refused"

# 7. force-push to main with marker → bypass
touch "$GIT_FORCE_PUSH_GATE_ALLOW_DIR/main"
run_case "force-push-main-bypass-marker" "git push --force origin main" "$WORK" 0 "git-push-gate-bypass"
rm -f "$GIT_FORCE_PUSH_GATE_ALLOW_DIR/main"

# 8. disable env var
GIT_FORCE_PUSH_GATE_DISABLE=1 run_case "disable-flag" "git push --force origin main" "$WORK" 0 ""

# --- v2.1 argv-parse regressions: literal flag chars inside a quoted
# commit-message body MUST NOT trip the gate. Substring match would; argv
# tokenization does not.
( cd "$WORK" && git checkout -q main )

# 9. commit on main with `--no-verify` inside the message body → allow.
run_case "commit-msg-mentions-no-verify" \
  'git commit -m "fix: handle --no-verify path in input parser"' "$WORK" 0 ""

# 10. -am variant with `--force-with-lease` literal in message → allow.
run_case "commit-am-msg-mentions-force" \
  'git commit -am "feat: --force-with-lease helper"' "$WORK" 0 ""

# 11. real `git push --no-verify origin main` still refused → preserved.
run_case "push-no-verify-still-refused" \
  "git push --no-verify origin main" "$WORK" 2 "git-push-gate-refused"

# 12. real `git commit --no-verify` (flag is argv, not message body) still
#     refused → preserved.
run_case "commit-no-verify-flag-still-refused" \
  "git commit --no-verify -m foo" "$WORK" 2 "git-push-gate-refused"

# --- v1.7.0 hook-rename evasion detection ---------------------------------
# 13. mv .git/hooks/pre-commit .git/hooks/commit-msg → refuse (any branch).
run_case "mv-pre-commit-to-commit-msg" \
  "mv .git/hooks/pre-commit .git/hooks/commit-msg" "$WORK" 2 "git-push-gate-refused"

# 14. cp variant of the same evasion → refuse.
run_case "cp-pre-commit-to-commit-msg" \
  "cp .git/hooks/pre-commit .git/hooks/commit-msg" "$WORK" 2 "git-push-gate-refused"

# 15. legitimate backup (no commit-msg in same chunk) → allow.
run_case "backup-pre-commit" \
  "cp .git/hooks/pre-commit /tmp/pre-commit-backup" "$WORK" 0 ""

# 16. literal in commit message body → allow (argv-parse-aware).
run_case "commit-msg-mentions-rename" \
  'git commit -m "fix: rename pre-commit to commit-msg in docs"' "$WORK" 0 ""

# 17. chained rename — pre-commit referenced AND commit-msg created → refuse.
#     `mv .git/hooks/pre-commit .git/hooks/pre-commit.bak && cp /tmp/x .git/hooks/commit-msg`
#     The mv chunk has only pre-commit (allow), but the cp chunk has commit-msg
#     without pre-commit (allow). Total: this DOES slip past — documented as
#     known limitation in SKILL.md. The detection covers the single-chunk
#     evasion which is the canonical pattern.
#     We DO refuse the literal `mv .git/hooks/pre-commit .git/hooks/commit-msg`,
#     which is the simplest expression of the attack. Sophisticated obfuscation
#     is beyond the gate's scope (documented).

# 18. git mv .git/hooks/pre-commit .git/hooks/commit-msg (porcelain variant) → refuse.
run_case "git-mv-pre-commit-to-commit-msg" \
  "git mv .git/hooks/pre-commit .git/hooks/commit-msg" "$WORK" 2 "git-push-gate-refused"

# 19. mv to .pre-commit.bak (unrelated rename, no commit-msg) → allow.
run_case "rename-pre-commit-to-bak" \
  "mv .git/hooks/pre-commit .git/hooks/pre-commit.bak" "$WORK" 0 ""

if [ "$fail" -eq 0 ]; then
  printf 'test-git-push-gate: PASS (17/17)\n'
fi
exit "$fail"
