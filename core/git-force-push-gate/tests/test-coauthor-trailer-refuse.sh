#!/usr/bin/env bash
# test-coauthor-trailer-refuse.sh — v1.10.0 trailer-refusal regression suite.
#
# Cases:
#   T-CTR-1  `git push` with HEAD commit carrying `Co-Authored-By: Claude
#            <noreply@anthropic.com>` → refuse exit 2 with stderr
#            "git-push-gate-refused" + reason="coauthor_trailer".
#   T-CTR-2  Same scenario but feature-branch (not main) → still refuse
#            (any-branch policy, analogous to no_verify).
#   T-CTR-3  Variant trailer "co-authored-by: Some Bot <bot@anthropic.com>"
#            (anthropic.com email match without literal "Claude") → refuse.
#   T-CTR-4  Plain commit with NO trailer → allow (no false positive).
#   T-CTR-5  Trailer with human co-author "Co-Authored-By: Jane Doe
#            <jane@example.com>" → allow (real human co-author preserved).
#   T-CTR-6  Trailer in HEAD~1 (older commit not yet pushed) → still
#            refuse (we scan @{upstream}..HEAD, not just HEAD).
#   T-CTR-7  GIT_FORCE_PUSH_GATE_ALLOW_CLAUDE_TRAILER=1 → bypass, exit 0.
#   T-CTR-8  GIT_FORCE_PUSH_GATE_DISABLE=1 → bypass, exit 0 (existing
#            global disable flag still wins).
#
# Note: this is a PreToolUse hook for `git push`. The hook reads the
# tool_input cwd, runs `git log` against @{upstream}..HEAD (or
# HEAD~50..HEAD if no upstream), and refuses when it finds the trailer.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
HOOK="$REPO_ROOT/core/git-force-push-gate/hooks/git-push-gate.sh"
TPL="$REPO_ROOT/core/git-force-push-gate/templates/protected-branches.txt"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a tmp git repo with no upstream and a controllable HEAD.
WORK="$TMP/work"
mkdir -p "$WORK"
(
  cd "$WORK"
  git init -q
  git config user.email t@t
  git config user.name t
  git commit -q --allow-empty -m "init: clean message"
  git checkout -q -B main 2>/dev/null || true
)

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

# Helper: synth a commit on top of HEAD with the given message.
seed_commit() {
  local msg="$1"
  (
    cd "$WORK"
    : > "scratch-$RANDOM-$RANDOM"
    git add -A
    git -c user.email=t@t -c user.name=t commit -q -m "$msg"
  )
}

# --- T-CTR-1: HEAD commit carries Claude trailer → refuse on push --------
seed_commit "$(printf 'feat: a thing\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n')"
run_case "claude-trailer-head-push-main" \
  "git push origin main" "$WORK" 2 "git-push-gate-refused"

# Verify the reason is coauthor_trailer (not force_push or no_verify).
TELEM_LAST="$(tail -n 1 "$TMP/.claude/telemetry.jsonl" 2>/dev/null || echo)"
if printf '%s' "$TELEM_LAST" | grep -q '"reason":"coauthor_trailer"'; then
  printf 'PASS: T-CTR-1.telem reason=coauthor_trailer recorded\n'
else
  printf 'FAIL: T-CTR-1.telem expected reason=coauthor_trailer; got=%s\n' "$TELEM_LAST" >&2
  fail=1
fi

# --- T-CTR-2: same trailer, feature branch → still refuse (any branch) --
(
  cd "$WORK"
  git checkout -q -b feat/personal 2>/dev/null
)
run_case "claude-trailer-head-push-feature" \
  "git push origin feat/personal" "$WORK" 2 "git-push-gate-refused"

# --- T-CTR-3: variant — anthropic.com email without literal "Claude" ---
(
  cd "$WORK"
  git checkout -q main 2>/dev/null
)
seed_commit "$(printf 'feat: variant trailer\n\nCo-Authored-By: Some Bot <bot@anthropic.com>\n')"
run_case "anthropic-email-trailer" \
  "git push origin main" "$WORK" 2 "git-push-gate-refused"

# --- T-CTR-4: plain commit, NO trailer → allow (no FP) ------------------
# Reset to a clean state so @{upstream}..HEAD path doesn't surface old
# trailer-bearing commits. Build a fresh worktree.
WORK2="$TMP/work-clean"
mkdir -p "$WORK2"
(
  cd "$WORK2"
  git init -q
  git config user.email t@t
  git config user.name t
  git commit -q --allow-empty -m "init: clean only"
  git checkout -q -B main 2>/dev/null || true
)
run_case "no-trailer-plain-push" \
  "git push origin main" "$WORK2" 0 ""

# --- T-CTR-5: human co-author trailer → allow (preserved) ---------------
(
  cd "$WORK2"
  : > some-file
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m "$(printf 'feat: human coauthor\n\nCo-Authored-By: Jane Doe <jane@example.com>\n')"
)
run_case "human-coauthor-allowed" \
  "git push origin main" "$WORK2" 0 ""

# --- T-CTR-6: trailer in HEAD~1 (older commit ahead of upstream) --------
WORK3="$TMP/work-older"
mkdir -p "$WORK3"
(
  cd "$WORK3"
  git init -q
  git config user.email t@t
  git config user.name t
  git commit -q --allow-empty -m "init"
  git checkout -q -B main 2>/dev/null || true
  : > older-1
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m "$(printf 'feat: older with trailer\n\nco-authored-by: Claude Opus <claude@anthropic.com>\n')"
  : > newer-1
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m "feat: newer clean"
)
run_case "trailer-in-older-commit" \
  "git push origin main" "$WORK3" 2 "git-push-gate-refused"

# --- T-CTR-7: explicit allow-trailer bypass env -------------------------
(
  cd "$WORK"
  git checkout -q main 2>/dev/null
)
GIT_FORCE_PUSH_GATE_ALLOW_CLAUDE_TRAILER=1 run_case "allow-trailer-bypass-env" \
  "git push origin main" "$WORK" 0 ""

# --- T-CTR-8: global disable flag still wins ----------------------------
GIT_FORCE_PUSH_GATE_DISABLE=1 run_case "global-disable-still-wins" \
  "git push origin main" "$WORK" 0 ""

if [ "$fail" -eq 0 ]; then
  printf 'test-coauthor-trailer-refuse: PASS\n'
fi
exit "$fail"
