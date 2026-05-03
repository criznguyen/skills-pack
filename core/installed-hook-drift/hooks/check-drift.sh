#!/usr/bin/env bash
# check-drift.sh — compare installed hooks vs canonical source.
#
# Walks $HOME/.claude/hooks/<group>/*.sh. For each installed hook, resolves
# the canonical counterpart at $REPO_ROOT/core/<group>/hooks/<basename>.
# Emits JSONL on stdout: one line per drift or orphan. Exit 0 always.
#
# REPO_ROOT resolution order:
#   1. $1 (positional argument)
#   2. $CLAUDE_SKILLS_REPO_ROOT env var
#   3. inferred from script location (../../.. relative to this file)
#
# Forbidden content (TM4): no LLM-spawn literals.

set -uo pipefail

HOME_DIR="${HOME:-/root}"
INSTALLED_BASE="${INSTALLED_HOOK_DRIFT_INSTALLED_BASE:-$HOME_DIR/.claude/hooks}"

# REPO_ROOT resolution.
REPO_ROOT=""
if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
  REPO_ROOT="$1"
elif [ -n "${CLAUDE_SKILLS_REPO_ROOT:-}" ]; then
  REPO_ROOT="$CLAUDE_SKILLS_REPO_ROOT"
else
  # Script is at <repo>/core/installed-hook-drift/hooks/check-drift.sh.
  # Walk up 3 dirs to get <repo>.
  SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
  SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd 2>/dev/null || echo)"
fi

# Validate REPO_ROOT looks like a claude-skills checkout.
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/core" ]; then
  printf '{"status":"error","reason":"REPO_ROOT not a claude-skills checkout","repo_root":"%s"}\n' "${REPO_ROOT//\"/}"
  exit 0
fi

# No installed hooks dir → nothing to check.
if [ ! -d "$INSTALLED_BASE" ]; then
  exit 0
fi

# sha256 helper that picks the platform tool.
sha256_of() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  else
    # No hash tool available — fall back to size+mtime as a weak signal.
    # Don't lie about a sha; emit a sentinel.
    printf 'no-hash-tool-%s' "$(stat -c '%s-%Y' "$f" 2>/dev/null || stat -f '%z-%m' "$f" 2>/dev/null || echo unknown)"
  fi
}

# JSON-string-escape helper for paths (handles \ and " only — paths with raw
# control bytes are extremely unlikely on a claude-skills install).
escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# Walk groups under INSTALLED_BASE.
for group_dir in "$INSTALLED_BASE"/*/; do
  [ -d "$group_dir" ] || continue
  group="$(basename "$group_dir")"
  for installed in "$group_dir"*.sh; do
    [ -f "$installed" ] || continue
    canonical="$REPO_ROOT/core/$group/hooks/$(basename "$installed")"
    inst_e="$(escape "$installed")"
    if [ ! -f "$canonical" ]; then
      printf '{"status":"orphan","installed":"%s","canonical":null,"group":"%s"}\n' \
        "$inst_e" "$(escape "$group")"
      continue
    fi
    inst_sha="$(sha256_of "$installed")"
    canon_sha="$(sha256_of "$canonical")"
    if [ "$inst_sha" != "$canon_sha" ]; then
      canon_e="$(escape "$canonical")"
      printf '{"status":"drift","installed":"%s","canonical":"%s","group":"%s","installed_sha":"%s","canonical_sha":"%s"}\n' \
        "$inst_e" "$canon_e" "$(escape "$group")" "${inst_sha//\"/}" "${canon_sha//\"/}"
    fi
  done
done

exit 0
