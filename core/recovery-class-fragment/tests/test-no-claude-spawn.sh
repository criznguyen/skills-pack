#!/usr/bin/env bash
# test-no-claude-spawn.sh — TM4 grep test.
# Hook source MUST NOT contain claude -p, Agent(, anthropic., or @anthropic.
# Mirrors core/quarantine-pack/tests/test-no-claude-spawn.sh.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
HOOKS_DIR="$REPO_ROOT/core/recovery-class-fragment/hooks"

fail=0
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  if grep -E '(claude\s+-p|Agent\s*\(|anthropic\.|@anthropic)' "$f" >/dev/null 2>&1; then
    printf 'FAIL: %s contains forbidden LLM-spawn literal (TM4 / NG6)\n' "$f" >&2
    grep -nE '(claude\s+-p|Agent\s*\(|anthropic\.|@anthropic)' "$f" >&2 || true
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  printf 'test-no-claude-spawn: PASS (no forbidden literals in hooks/*.sh)\n'
fi
exit "$fail"
