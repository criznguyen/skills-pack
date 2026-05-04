#!/usr/bin/env bash
# test-install-mamd-canonical.sh — regression test for v1.9.1 §18.
#
# Reproduces the v1.8.0 missed-ship: multi-agent-merge-discipline (MAMD)
# shipped without an install § so operators registered the hook manually
# with command path `${CLAUDE_PROJECT_DIR}/.claude/skills/multi-agent-merge-discipline/hooks/pre-commit-strip-gen.sh`,
# which fails on every Bash invocation outside a project that vendored the
# skill into `.claude/skills/`. v1.9.1 §18 installs the hook globally and
# rewrites the broken path on next install.sh run.
#
# Asserts:
#   1. Fresh install: MAMD hook registered with command pointing to
#      $HOME/.claude/hooks/multi-agent-merge-discipline/pre-commit-strip-gen.sh
#      and matcher "Bash". Hook script exists + executable.
#   2. Idempotent: re-running install does NOT add a duplicate entry.
#   3. Drift recovery: a stale entry with the broken
#      `${CLAUDE_PROJECT_DIR}/.claude/skills/...` literal is REWRITTEN to
#      the canonical global path on install (no duplicate, no surviving
#      broken path).
#   4. Unrelated PreToolUse entries (not referencing
#      `pre-commit-strip-gen.sh`) survive untouched.
#
# Runs against an isolated $HOME — never mutates the real ~/.claude/.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
INSTALL_SH="$REPO_ROOT/core/governance-pack/install.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP test-install-mamd-canonical: jq not installed (install path requires jq)" >&2
  exit 0
fi
if [ ! -x "$INSTALL_SH" ]; then
  echo "FAIL: install.sh missing or not executable at $INSTALL_SH" >&2
  exit 1
fi

TMPHOME="$(mktemp -d -t cs-mamd-test.XXXXXX)"
cleanup() { rm -rf "$TMPHOME"; }
trap cleanup EXIT

mkdir -p "$TMPHOME/.claude"

EXPECTED_PATH="$TMPHOME/.claude/hooks/multi-agent-merge-discipline/pre-commit-strip-gen.sh"
EXPECTED_MATCHER='Bash'

# ----------------------------------------------------------------------
# Phase 1: fresh install (no prior settings.json with MAMD).
# Seed a settings.json with an UNRELATED Bash entry to cover assertion 4.
# ----------------------------------------------------------------------
cat > "$TMPHOME/.claude/settings.json" <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type":"command","command":"/sentinel/unrelated-bash-hook.sh","timeout":5000}
        ]
      }
    ]
  }
}
EOF

HOME="$TMPHOME" bash "$INSTALL_SH" >"$TMPHOME/install-1.log" 2>&1 || {
  echo "FAIL phase 1: install.sh exited non-zero" >&2
  tail -30 "$TMPHOME/install-1.log" >&2
  exit 1
}

# Assertion 1a: hook script installed + executable.
if [ ! -x "$EXPECTED_PATH" ]; then
  echo "FAIL assertion 1a: $EXPECTED_PATH missing or not executable" >&2
  ls -la "$TMPHOME/.claude/hooks/multi-agent-merge-discipline/" >&2 2>/dev/null || true
  exit 1
fi

# Assertion 1b: matcher canonical, command points to the global $HOME path.
ACTUAL_MATCHER="$(jq -r --arg c "$EXPECTED_PATH" '
  .hooks.PreToolUse[]? | select(.hooks[]?.command == $c) | .matcher
' "$TMPHOME/.claude/settings.json")"
if [ "$ACTUAL_MATCHER" != "$EXPECTED_MATCHER" ]; then
  echo "FAIL assertion 1b: MAMD matcher = '$ACTUAL_MATCHER', want '$EXPECTED_MATCHER'" >&2
  exit 1
fi

# Assertion 1c: exactly ONE MAMD entry.
COUNT="$(jq --arg c "$EXPECTED_PATH" \
  '[.hooks.PreToolUse[]? | select(.hooks[]?.command == $c)] | length' \
  "$TMPHOME/.claude/settings.json")"
if [ "$COUNT" != "1" ]; then
  echo "FAIL assertion 1c: MAMD entry count = $COUNT, want 1" >&2
  exit 1
fi

# ----------------------------------------------------------------------
# Phase 2: idempotency — re-running install MUST NOT add a duplicate.
# ----------------------------------------------------------------------
HOME="$TMPHOME" bash "$INSTALL_SH" >"$TMPHOME/install-2.log" 2>&1 || {
  echo "FAIL phase 2: install.sh exited non-zero on second run" >&2
  tail -30 "$TMPHOME/install-2.log" >&2
  exit 1
}

COUNT_AFTER_RERUN="$(jq --arg c "$EXPECTED_PATH" \
  '[.hooks.PreToolUse[]? | select(.hooks[]?.command == $c)] | length' \
  "$TMPHOME/.claude/settings.json")"
if [ "$COUNT_AFTER_RERUN" != "1" ]; then
  echo "FAIL assertion 2: re-run produced duplicate (count=$COUNT_AFTER_RERUN, want 1)" >&2
  exit 1
fi

# ----------------------------------------------------------------------
# Phase 3: drift recovery — seed a fresh settings.json that contains a
# stale entry with the broken `${CLAUDE_PROJECT_DIR}/.claude/skills/...`
# path (the v1.8.0 manual-registration shape). install.sh must REWRITE it.
# ----------------------------------------------------------------------
TMPHOME2="$(mktemp -d -t cs-mamd-drift.XXXXXX)"
cleanup2() { rm -rf "$TMPHOME" "$TMPHOME2"; }
trap cleanup2 EXIT
mkdir -p "$TMPHOME2/.claude"

cat > "$TMPHOME2/.claude/settings.json" <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type":"command","command":"/sentinel/unrelated-bash-hook.sh","timeout":5000}
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {"type":"command","command":"${CLAUDE_PROJECT_DIR}/.claude/skills/multi-agent-merge-discipline/hooks/pre-commit-strip-gen.sh","timeout":5000}
        ]
      }
    ]
  }
}
EOF

HOME="$TMPHOME2" bash "$INSTALL_SH" >"$TMPHOME2/install-drift.log" 2>&1 || {
  echo "FAIL phase 3: install.sh exited non-zero on drift recovery" >&2
  tail -30 "$TMPHOME2/install-drift.log" >&2
  exit 1
}

DRIFT_EXPECTED_PATH="$TMPHOME2/.claude/hooks/multi-agent-merge-discipline/pre-commit-strip-gen.sh"

# Assertion 3a: broken `${CLAUDE_PROJECT_DIR}` literal is GONE.
BROKEN_COUNT="$(jq '[.hooks.PreToolUse[]? | .hooks[]? | select(.command | tostring | test("CLAUDE_PROJECT_DIR.*pre-commit-strip-gen"))] | length' \
  "$TMPHOME2/.claude/settings.json")"
if [ "$BROKEN_COUNT" != "0" ]; then
  echo "FAIL assertion 3a: broken \${CLAUDE_PROJECT_DIR} entry survived (count=$BROKEN_COUNT, want 0)" >&2
  jq '.hooks.PreToolUse' "$TMPHOME2/.claude/settings.json" >&2
  exit 1
fi

# Assertion 3b: canonical global-path entry is present.
CANONICAL_COUNT="$(jq --arg c "$DRIFT_EXPECTED_PATH" \
  '[.hooks.PreToolUse[]? | select(.hooks[]?.command == $c) | select(.matcher == "Bash")] | length' \
  "$TMPHOME2/.claude/settings.json")"
if [ "$CANONICAL_COUNT" != "1" ]; then
  echo "FAIL assertion 3b: canonical MAMD entry count = $CANONICAL_COUNT, want 1" >&2
  jq '.hooks.PreToolUse' "$TMPHOME2/.claude/settings.json" >&2
  exit 1
fi

# Assertion 3c: total pre-commit-strip-gen.sh references = exactly 1
# (no leftover stale entry, no duplicate).
TOTAL_REFS="$(jq '[.hooks.PreToolUse[]? | .hooks[]? | select(.command | tostring | test("(^|/)pre-commit-strip-gen\\.sh$"))] | length' \
  "$TMPHOME2/.claude/settings.json")"
if [ "$TOTAL_REFS" != "1" ]; then
  echo "FAIL assertion 3c: total pre-commit-strip-gen.sh references = $TOTAL_REFS, want 1" >&2
  jq '.hooks.PreToolUse' "$TMPHOME2/.claude/settings.json" >&2
  exit 1
fi

# Assertion 4: unrelated /sentinel/unrelated-bash-hook.sh entry survived
# in BOTH phase-1 settings AND phase-3 settings.
SENTINEL_1="$(jq '[.hooks.PreToolUse[]? | .hooks[]? | select(.command == "/sentinel/unrelated-bash-hook.sh")] | length' \
  "$TMPHOME/.claude/settings.json")"
SENTINEL_3="$(jq '[.hooks.PreToolUse[]? | .hooks[]? | select(.command == "/sentinel/unrelated-bash-hook.sh")] | length' \
  "$TMPHOME2/.claude/settings.json")"
if [ "$SENTINEL_1" != "1" ] || [ "$SENTINEL_3" != "1" ]; then
  echo "FAIL assertion 4: unrelated sentinel entry disturbed (phase1=$SENTINEL_1, phase3=$SENTINEL_3, want 1+1)" >&2
  exit 1
fi

echo "PASS test-install-mamd-canonical: fresh install + idempotent + drift recovery + sentinel preserved"
exit 0
