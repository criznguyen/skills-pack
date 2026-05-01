#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
SCAN_DIR="$REPO_ROOT/core/eval-contamination-probe"
fail=0
# This skill ships no hooks/*.sh; only the test scripts. TM4 still applies.
for f in "$SCAN_DIR"/tests/*.sh; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in
    test-no-claude-spawn.sh) continue ;;
  esac
  if grep -E '(claude\s+-p|Agent\s*\(|anthropic\.|@anthropic)' "$f" >/dev/null 2>&1; then
    printf 'FAIL: %s contains forbidden literal\n' "$f" >&2
    fail=1
  fi
done
[ "$fail" -eq 0 ] && printf 'test-no-claude-spawn: PASS\n'
exit "$fail"
