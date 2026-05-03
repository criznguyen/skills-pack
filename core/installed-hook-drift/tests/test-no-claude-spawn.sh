#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
HOOKS_DIR="$REPO_ROOT/core/installed-hook-drift/hooks"
fail=0
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  if grep -E '(claude\s+-p|Agent\s*\(|anthropic\.|@anthropic)' "$f" >/dev/null 2>&1; then
    printf 'FAIL: %s contains forbidden literal\n' "$f" >&2
    fail=1
  fi
done
[ "$fail" -eq 0 ] && printf 'test-no-claude-spawn: PASS\n'
exit "$fail"
