#!/usr/bin/env bash
# Tests for pre-commit-strip-gen.sh
set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$THIS_DIR/../hooks/pre-commit-strip-gen.sh"

PASS=0
FAIL=0
log() { printf '%s\n' "$*" >&2; }
assert_eq() {
  local got="$1" want="$2" name="$3"
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); log "PASS: $name"
  else FAIL=$((FAIL+1)); log "FAIL: $name | got=$got want=$want"; fi
}

# Test 1: Non-Bash tool → no-op exit 0
RESULT="$(echo '{"tool_name":"Edit","tool_input":{"file_path":"foo.go"}}' | "$HOOK" 2>&1; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && PASS=$((PASS+1)) && log "PASS: t1 non-Bash skips" || { FAIL=$((FAIL+1)); log "FAIL: t1 non-Bash skips | $RESULT"; }

# Test 2: Bash but not git commit → no-op exit 0
RESULT="$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | "$HOOK" 2>&1; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && PASS=$((PASS+1)) && log "PASS: t2 unrelated bash skips" || { FAIL=$((FAIL+1)); log "FAIL: t2 | $RESULT"; }

# Test 3: git commit-tree (not commit) → no-op
RESULT="$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit-tree HEAD"}}' | "$HOOK" 2>&1; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && PASS=$((PASS+1)) && log "PASS: t3 commit-tree (not commit) skips" || { FAIL=$((FAIL+1)); log "FAIL: t3 | $RESULT"; }

# Test 4: git commit but no allowlist → silent no-op (skill opt-in)
TMPDIR_T4=$(mktemp -d)
( cd "$TMPDIR_T4" && git init -q && git commit --allow-empty -m "init" -q )
RESULT="$(CLAUDE_PROJECT_DIR="$TMPDIR_T4" sh -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m foo\"}}' | $HOOK" 2>&1; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && PASS=$((PASS+1)) && log "PASS: t4 no allowlist silent" || { FAIL=$((FAIL+1)); log "FAIL: t4 | $RESULT"; }
rm -rf "$TMPDIR_T4"

# Test 5: git commit with allowlist + matching staged file → stripped
TMPDIR_T5=$(mktemp -d)
( cd "$TMPDIR_T5" && git init -q && \
  mkdir -p .claude/skills/multi-agent-merge-discipline gen && \
  echo "gen/**" > .claude/skills/multi-agent-merge-discipline/gen-paths.txt && \
  echo "// generated" > gen/x.go && \
  echo "// hand-written" > main.go && \
  git add gen/x.go main.go && \
  git -c user.email=t@t -c user.name=t commit --allow-empty -m "seed" -q && \
  echo "// new gen" > gen/y.go && \
  echo "// new code" > main.go && \
  git add gen/y.go main.go )

RESULT="$(CLAUDE_PROJECT_DIR="$TMPDIR_T5" sh -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m wip\"}}' | $HOOK" 2>&1)"
( cd "$TMPDIR_T5" && \
  STAGED_AFTER="$(git diff --cached --name-only)" && \
  if echo "$STAGED_AFTER" | grep -q '^gen/y.go$'; then \
    log "FAIL: t5 gen/y.go should be unstaged but is still staged"; FAIL=$((FAIL+1)); \
  else \
    log "PASS: t5 gen/y.go was unstaged"; PASS=$((PASS+1)); \
  fi && \
  if echo "$STAGED_AFTER" | grep -q '^main.go$'; then \
    log "PASS: t5 main.go remains staged"; PASS=$((PASS+1)); \
  else \
    log "FAIL: t5 main.go should be staged but was unstaged"; FAIL=$((FAIL+1)); \
  fi )
echo "$RESULT" | grep -q "stripped" && PASS=$((PASS+1)) && log "PASS: t5 stderr reports stripped" || { FAIL=$((FAIL+1)); log "FAIL: t5 stderr should report stripped | $RESULT"; }
rm -rf "$TMPDIR_T5"

# Test 6: DISABLE env var → no-op
TMPDIR_T6=$(mktemp -d)
( cd "$TMPDIR_T6" && git init -q && \
  mkdir -p .claude/skills/multi-agent-merge-discipline gen && \
  echo "gen/**" > .claude/skills/multi-agent-merge-discipline/gen-paths.txt )
RESULT="$(MULTI_AGENT_MERGE_DISCIPLINE_DISABLE=1 CLAUDE_PROJECT_DIR="$TMPDIR_T6" sh -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m wip\"}}' | $HOOK" 2>&1; echo "EXIT=$?")"
echo "$RESULT" | grep -q "EXIT=0" && [ -z "$(echo "$RESULT" | grep stripped)" ] && PASS=$((PASS+1)) && log "PASS: t6 DISABLE bypasses" || { FAIL=$((FAIL+1)); log "FAIL: t6 | $RESULT"; }
rm -rf "$TMPDIR_T6"

log ""
log "Results: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
