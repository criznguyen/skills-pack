#!/usr/bin/env bash
# deny-prod-paths.sh — PreToolUse hook for Edit/Write/MultiEdit.
#
# Trigger: PreToolUse on Edit, Write, MultiEdit.
# Behavior:
#   - Reads tool input JSON from stdin (per Claude Code hook contract).
#   - Extracts the target file_path.
#   - v1.4.3+: FIRST checks per-project allowlist
#     (`<project_root>/.claude/governance-allow.txt` by default;
#     overridable via $GOVERNANCE_PACK_ALLOW_FILE). project_root is detected
#     by walking up from file_path's directory looking for .git/. If a glob
#     pattern in the allow-file matches, the write is allowed (exit 0) and
#     audit-logged to <project_root>/.claude/state/governance-allow.jsonl
#     (overridable via $GOVERNANCE_PACK_AUDIT_LOG_FILE).
#   - Otherwise, compares against patterns in $GOVERNANCE_PACK_PROD_PATHS_FILE
#     (default: ~/.claude/prod-paths.txt).
#   - If matched (and NOT allowed), exits 2 with stderr message → Claude sees the block.
#   - On infra failure (missing patterns file, jq missing, malformed JSON), exits 0
#     so that the hook NEVER blocks legitimate work due to its own bugs.
#
# Composes with: core-config/pre-edit-stash.sh (runs before this in the same matcher;
# stash already taken when we deny — harmless).

set -uo pipefail

PATTERNS_FILE="${GOVERNANCE_PACK_PROD_PATHS_FILE:-$HOME/.claude/prod-paths.txt}"

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

extract_tool_name() {
  if command -v jq >/dev/null 2>&1; then
    echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    echo "$INPUT" | python3 -c 'import json,sys
try:
  print(json.load(sys.stdin).get("tool_name") or "")
except Exception:
  pass' 2>/dev/null
  else
    echo "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -n1 | sed -E 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
  fi
}

FILE_PATH="$(extract_path)"
[ -z "$FILE_PATH" ] && exit 0
TOOL_NAME="$(extract_tool_name)"
[ -z "$TOOL_NAME" ] && TOOL_NAME="unknown"

# Make path absolute so glob patterns like /home/.../** match consistently.
case "$FILE_PATH" in
  /*) ABS_PATH="$FILE_PATH" ;;
  *)  ABS_PATH="${PWD}/${FILE_PATH}" ;;
esac

# Enable bash's globstar/extglob for ** matching.
shopt -s extglob globstar nullglob 2>/dev/null || true

# ---- v1.4.3+: per-project allowlist (allow-wins) -----------------------------
#
# Walk up from ABS_PATH's parent directory looking for a .git/ ancestor.
# That ancestor IS the project root. If <project_root>/.claude/governance-allow.txt
# (or $GOVERNANCE_PACK_ALLOW_FILE) exists and any pattern matches the candidate
# path, allow the write and audit-log it.
find_project_root() {
  local dir="$1"
  # If dir is a file, walk from its parent.
  [ -f "$dir" ] && dir="$(dirname "$dir")"
  # Resolve any ".." but don't fail if path doesn't exist yet (new file in existing dir).
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
      printf '%s' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

PROJECT_ROOT="$(find_project_root "$ABS_PATH" 2>/dev/null || true)"

if [ -n "$PROJECT_ROOT" ]; then
  ALLOW_FILE="${GOVERNANCE_PACK_ALLOW_FILE:-$PROJECT_ROOT/.claude/governance-allow.txt}"
  AUDIT_LOG="${GOVERNANCE_PACK_AUDIT_LOG_FILE:-$PROJECT_ROOT/.claude/state/governance-allow.jsonl}"

  if [ -f "$ALLOW_FILE" ]; then
    while IFS= read -r allow_pattern || [ -n "$allow_pattern" ]; do
      allow_pattern="${allow_pattern%$'\r'}"
      [ -z "$allow_pattern" ] && continue
      case "$allow_pattern" in
        \#*) continue ;;
      esac

      # shellcheck disable=SC2053
      if [[ "$ABS_PATH" == $allow_pattern ]] || [[ "$FILE_PATH" == $allow_pattern ]]; then
        # Audit-log the allow (best-effort; never break the hook on log failure).
        mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
        local_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
        # JSONL with manual escaping of double-quotes and backslashes in path strings.
        # (Paths shouldn't contain control chars; if they do, telemetry is best-effort.)
        esc_file="${FILE_PATH//\\/\\\\}"; esc_file="${esc_file//\"/\\\"}"
        esc_pattern="${allow_pattern//\\/\\\\}"; esc_pattern="${esc_pattern//\"/\\\"}"
        esc_allow="${ALLOW_FILE//\\/\\\\}"; esc_allow="${esc_allow//\"/\\\"}"
        esc_tool="${TOOL_NAME//\\/\\\\}"; esc_tool="${esc_tool//\"/\\\"}"
        printf '{"ts":"%s","tool":"%s","file_path":"%s","matched_pattern":"%s","allow_file":"%s","reason":"governance-allow match"}\n' \
          "$local_ts" "$esc_tool" "$esc_file" "$esc_pattern" "$esc_allow" \
          >> "$AUDIT_LOG" 2>/dev/null || true
        exit 0
      fi
    done < "$ALLOW_FILE"
  fi
fi

# ---- universal denylist (unchanged, fall-through after no allow match) -------

# Graceful: if patterns file is missing, allow through.
[ -f "$PATTERNS_FILE" ] || exit 0

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
[governance-pack/deny-prod-paths] For per-project audit-mode allowlist: add the path glob to
[governance-pack/deny-prod-paths]   <project_root>/.claude/governance-allow.txt (v1.4.3+).
EOF
    exit 2
  fi
done < "$PATTERNS_FILE"

exit 0
