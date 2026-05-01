#!/usr/bin/env bash
# deny-prod-paths.sh — PreToolUse hook for Edit/Write/MultiEdit.
#
# Trigger: PreToolUse on Edit, Write, MultiEdit.
# Behavior:
#   - Reads tool input JSON from stdin (per Claude Code hook contract).
#   - Extracts the target file_path.
#   - Compares against patterns in $GOVERNANCE_PACK_PROD_PATHS_FILE
#     (default: ~/.claude/prod-paths.txt).
#   - If matched, exits 2 with stderr message → Claude sees the block.
#   - On infra failure (missing patterns file, jq missing, malformed JSON), exits 0
#     so that the hook NEVER blocks legitimate work due to its own bugs.
#
# Composes with: core-config/pre-edit-stash.sh (runs before this in the same matcher;
# stash already taken when we deny — harmless).

set -uo pipefail

PATTERNS_FILE="${GOVERNANCE_PACK_PROD_PATHS_FILE:-$HOME/.claude/prod-paths.txt}"

# Graceful: if patterns file is missing, allow through.
[ -f "$PATTERNS_FILE" ] || exit 0

# Read JSON from stdin.
INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

# Extract file_path. Try jq first, fall back to python3 (one or the other is
# always present on Linux/macOS dev boxes). Fall back to grep if both missing.
extract_path() {
  if command -v jq >/dev/null 2>&1; then
    echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    echo "$INPUT" | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin).get("tool_input",{})
  print(d.get("file_path") or d.get("path") or "")
except Exception:
  pass' 2>/dev/null
  else
    # Last-resort grep: look for "file_path":"..." literal.
    echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -n1 | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
  fi
}

FILE_PATH="$(extract_path)"
[ -z "$FILE_PATH" ] && exit 0

# Make path absolute so glob patterns like /home/.../** match consistently.
case "$FILE_PATH" in
  /*) ABS_PATH="$FILE_PATH" ;;
  *)  ABS_PATH="${PWD}/${FILE_PATH}" ;;
esac

# Check against each pattern. Use bash's [[ ... == glob ]] with extglob/globstar.
shopt -s extglob globstar nullglob 2>/dev/null || true

while IFS= read -r pattern || [ -n "$pattern" ]; do
  # Skip blanks and comments.
  pattern="${pattern%$'\r'}"
  [ -z "$pattern" ] && continue
  case "$pattern" in
    \#*) continue ;;
  esac

  # Use bash extended glob match. The double-star (**) requires globstar.
  # shellcheck disable=SC2053
  if [[ "$ABS_PATH" == $pattern ]] || [[ "$FILE_PATH" == $pattern ]]; then
    cat >&2 <<EOF
[governance-pack/deny-prod-paths] BLOCKED: ${FILE_PATH}
[governance-pack/deny-prod-paths] Matched pattern: ${pattern}
[governance-pack/deny-prod-paths] Source: ${PATTERNS_FILE}
[governance-pack/deny-prod-paths] To unblock this path: comment out the pattern in the file above,
[governance-pack/deny-prod-paths] or unset GOVERNANCE_PACK_PROD_PATHS_FILE for a one-off bypass.
EOF
    exit 2
  fi
done < "$PATTERNS_FILE"

exit 0
