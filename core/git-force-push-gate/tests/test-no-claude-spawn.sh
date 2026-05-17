#!/usr/bin/env bash
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
HOOKS_DIR="$REPO_ROOT/core/git-force-push-gate/hooks"

fail=0
for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  # TM4 / NG6: scan for actual LLM-spawn / SDK-invocation patterns, NOT
  # bare "anthropic.com" email-domain references which legitimately appear
  # in commit-trailer detection regex + docstring examples (v1.10.0).
  if grep -E '(claude[[:space:]]+-p|Agent[[:space:]]*\(|anthropic\.(api|client|messages|Anthropic|chat|completions|tools|files|batches|with_options|stream)|@anthropic-ai/|from[[:space:]]+anthropic[[:space:]]+import|import[[:space:]]+anthropic([[:space:]]|$))' "$f" >/dev/null 2>&1; then
    printf 'FAIL: %s contains forbidden LLM-spawn literal (TM4 / NG6)\n' "$f" >&2
    fail=1
  fi
done

[ "$fail" -eq 0 ] && printf 'test-no-claude-spawn: PASS\n'
exit "$fail"
