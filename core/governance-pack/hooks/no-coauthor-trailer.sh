#!/usr/bin/env bash
# no-coauthor-trailer.sh — PreToolUse hook on Bash, scoped to `git commit`.
#
# Trigger: PreToolUse on Bash.
# Behavior:
#   - Reads tool input JSON from stdin.
#   - If the command is a `git commit ... -m "<msg>"` (or `<<EOF` HEREDOC commit)
#     AND the message contains `Co-Authored-By: Claude` (case-insensitive),
#     blocks with exit 2 and tells Claude to remove the trailer and retry.
#   - Preserves human co-authors: any `Co-Authored-By:` line that is NOT Claude
#     is allowed through. Match is case-insensitive on the email/name part.
#   - Non-commit Bash commands → exit 0 (pass).
#   - Infra failure → exit 0 (never block due to our own bugs).
#
# Why block-and-retry rather than rewrite: Claude Code's PreToolUse hook contract
# does not natively support tool-input mutation in a forward-compatible way.
# Blocking with a clear error message is the deterministic path; Claude will
# regenerate the commit without the trailer on retry.
#
# Per user feedback: feedback_no_claude_coauthor (operator-specific rule for
# opinions; safe default for any solo-dev workflow that wants
# clean attribution).

set -uo pipefail

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

# Extract command. Try jq → python3 → grep fallback chain.
extract_cmd() {
  if command -v jq >/dev/null 2>&1; then
    echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    echo "$INPUT" | python3 -c 'import json,sys
try:
  print(json.load(sys.stdin).get("tool_input",{}).get("command") or "")
except Exception:
  pass' 2>/dev/null
  else
    echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' \
      | head -n1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"(.*)"$/\1/' \
      | sed 's/\\"/"/g; s/\\n/\n/g'
  fi
}

CMD="$(extract_cmd)"
[ -z "$CMD" ] && exit 0

# Only inspect git commit commands.
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# Look for a Co-Authored-By line that names "Claude" or an Anthropic / Claude email.
# Pattern intentionally loose to catch variants:
#   Co-Authored-By: Claude <noreply@anthropic.com>
#   Co-authored-by: Claude Opus 4.x <noreply@anthropic.com>
#   co-authored-by: claude-code@anthropic.com
# but tight enough to NOT match a real human:
#   Co-Authored-By: Jane Doe <jane@example.com>
if echo "$CMD" | grep -qiE 'co-authored-by:[[:space:]]*[^<\n]*claude([^<\n]*<|@)' \
   || echo "$CMD" | grep -qiE 'co-authored-by:[[:space:]]*[^<\n]*<[^>]*anthropic\.com>'; then
  cat >&2 <<'EOF'
[governance-pack/no-coauthor-trailer] BLOCKED: commit message contains `Co-Authored-By: Claude` trailer.
[governance-pack/no-coauthor-trailer] Per local policy (feedback_no_claude_coauthor), Claude must NOT be
[governance-pack/no-coauthor-trailer] listed as co-author on commits. Human co-authors are allowed.
[governance-pack/no-coauthor-trailer]
[governance-pack/no-coauthor-trailer] Action: remove the trailer (and the blank line above it) from the
[governance-pack/no-coauthor-trailer] commit message and retry. Other Co-Authored-By: <human> trailers
[governance-pack/no-coauthor-trailer] are preserved.
EOF
  exit 2
fi

exit 0
