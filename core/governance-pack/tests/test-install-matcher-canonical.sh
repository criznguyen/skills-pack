#!/usr/bin/env bash
# test-install-matcher-canonical.sh — regression test for v1.7.1.
#
# Reproduces the v1.7.0 install bug: a v1.6.0-shaped settings.json with the
# old matcher "Read" for cache-mtime-on-read.sh would survive `install.sh`
# unchanged because the substring grep only checked existence of
# `file-stat-check`, never the matcher value.
#
# Asserts:
#   1. After install.sh runs, the cache-mtime PostToolUse matcher equals
#      the canonical "Read|Edit|Write|MultiEdit".
#   2. No duplicate cache-mtime PostToolUse entry exists (the stale entry
#      must be removed in place, not appended alongside).
#   3. The pre-existing entries that install.sh did NOT touch survive.
#
# Runs against an isolated $HOME — never mutates the real ~/.claude/.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
INSTALL_SH="$REPO_ROOT/core/governance-pack/install.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP test-install-matcher-canonical: jq not installed (install path requires jq)" >&2
  exit 0
fi
if [ ! -x "$INSTALL_SH" ]; then
  echo "FAIL: install.sh missing or not executable at $INSTALL_SH" >&2
  exit 1
fi

TMPHOME="$(mktemp -d -t cs-install-test.XXXXXX)"
cleanup() { rm -rf "$TMPHOME"; }
trap cleanup EXIT

mkdir -p "$TMPHOME/.claude"

# Seed v1.6.0-shaped settings.json: matcher is the OLD "Read" value, plus
# an unrelated entry the installer must NOT disturb (sentinel for assertion 3).
cat > "$TMPHOME/.claude/settings.json" <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {"type":"command","command":"REPLACE_CACHE_PATH","timeout":5000}
        ]
      },
      {
        "matcher": ".*",
        "hooks": [
          {"type":"command","command":"/sentinel/unrelated-hook.sh","timeout":5000}
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {"type":"command","command":"REPLACE_CHECK_PATH","timeout":5000}
        ]
      }
    ]
  }
}
EOF

# install.sh writes hooks under $HOME/.claude/hooks/<skill>/, so the
# expected commands reference TMPHOME, not the real ~.
CACHE_PATH="$TMPHOME/.claude/hooks/file-write-stale-stat-refusal/cache-mtime-on-read.sh"
CHECK_PATH="$TMPHOME/.claude/hooks/file-write-stale-stat-refusal/file-stat-check.sh"
sed -i "s#REPLACE_CACHE_PATH#$CACHE_PATH#" "$TMPHOME/.claude/settings.json"
sed -i "s#REPLACE_CHECK_PATH#$CHECK_PATH#" "$TMPHOME/.claude/settings.json"

# Run install with TMPHOME as $HOME. install.sh derives CLAUDE_HOME from $HOME.
HOME="$TMPHOME" bash "$INSTALL_SH" >"$TMPHOME/install.log" 2>&1 || {
  echo "FAIL: install.sh exited non-zero" >&2
  tail -30 "$TMPHOME/install.log" >&2
  exit 1
}

# Assertion 1: cache-mtime matcher canonicalized.
ACTUAL_MATCHER="$(jq -r --arg c "$CACHE_PATH" '
  .hooks.PostToolUse[]? | select(.hooks[]?.command == $c) | .matcher
' "$TMPHOME/.claude/settings.json")"
EXPECTED='Read|Edit|Write|MultiEdit'
if [ "$ACTUAL_MATCHER" != "$EXPECTED" ]; then
  echo "FAIL assertion 1: cache-mtime matcher = '$ACTUAL_MATCHER', want '$EXPECTED'" >&2
  exit 1
fi

# Assertion 2: exactly ONE cache-mtime PostToolUse entry (no duplicate-add).
COUNT="$(jq --arg c "$CACHE_PATH" '
  [.hooks.PostToolUse[]? | select(.hooks[]?.command == $c)] | length
' "$TMPHOME/.claude/settings.json")"
if [ "$COUNT" != "1" ]; then
  echo "FAIL assertion 2: cache-mtime entry count = $COUNT, want 1 (stale entry not removed in place)" >&2
  exit 1
fi

# Assertion 3: unrelated sentinel entry survives.
SENTINEL="$(jq -r '
  [.hooks.PostToolUse[]? | select(.hooks[]?.command == "/sentinel/unrelated-hook.sh")] | length
' "$TMPHOME/.claude/settings.json")"
if [ "$SENTINEL" != "1" ]; then
  echo "FAIL assertion 3: unrelated sentinel entry was disturbed (count=$SENTINEL, want 1)" >&2
  exit 1
fi

echo "PASS test-install-matcher-canonical: matcher canonicalized in place, no duplicates, sentinel preserved"
exit 0
