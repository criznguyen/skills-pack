#!/usr/bin/env bash
# pre-commit-strip-gen.sh — PreToolUse(Bash).
#
# When the agent invokes `git commit` (directly or via shell pipeline),
# unstage paths matching the per-project allowlist at
#   $CLAUDE_PROJECT_DIR/.claude/skills/multi-agent-merge-discipline/gen-paths.txt
# Each line is a glob pattern (relative to project root) of an auto-
# generated file class (sqlc gen, ctxq, proto stubs, OpenAPI clients).
#
# Rationale: when N parallel sub-agents commit auto-generated files,
# each agent regenerates from its subset of hand-written sources,
# producing diff-overlapping interface methods/struct fields. Stripping
# the auto-gen files from each sub-agent commit shifts regeneration to
# the orchestrator post-merge, where one canonical run produces the
# union of all sub-agents' additions and zero textual merge conflicts.
#
# Forbidden content (TM4): no LLM-spawn literals.
# Origin: docs/research/v1.8-ideas/multi-agent-merge-discipline.md (v1.8).

set -uo pipefail

case "${MULTI_AGENT_MERGE_DISCIPLINE_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ALLOW_FILE="$PROJECT_DIR/.claude/skills/multi-agent-merge-discipline/gen-paths.txt"
HOME_DIR="${HOME:-/root}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null || true

emit_telemetry() {
  local action="$1" count="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"event":"multi-agent-merge-discipline","ts":"%s","action":"%s","stripped_count":%s}\n' \
    "$ts" "$action" "${count:-0}" >> "$TELEM_FILE" 2>/dev/null || true
}

# Parse tool_name + command. Only fire on Bash + commit invocation.
TOOL_NAME=""
COMMAND=""
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
  COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
elif command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: print(""); print(""); sys.exit(0)
ti = d.get("tool_input") or {}
if not isinstance(ti, dict): ti = {}
print(d.get("tool_name", "") or "")
print(ti.get("command", "") or "")
' 2>/dev/null)"
  TOOL_NAME="$(printf '%s' "$PARSED" | sed -n '1p')"
  COMMAND="$(printf '%s' "$PARSED" | sed -n '2,$p')"
else
  exit 0
fi

[ "$TOOL_NAME" = "Bash" ] || exit 0
[ -n "$COMMAND" ] || exit 0

# Heuristic: detect git commit. Match common patterns:
#   git commit ...
#   git commit -m "..."
#   cd /path && git commit ...
#   foo && git commit ...
# Use word-boundary regex; we DO NOT match `git commit-tree` or merely
# the literal substring "commit" in unrelated commands.
if ! printf '%s' "$COMMAND" | grep -qE '(^|[[:space:];&|])git[[:space:]]+commit([[:space:]]|$)'; then
  exit 0
fi

# Allowlist file required to do anything; absent → silent no-op (skill
# is opt-in per project).
[ -f "$ALLOW_FILE" ] || { emit_telemetry "no-allowlist" 0; exit 0; }

# Read patterns. Skip blank + comment lines.
mapfile -t PATTERNS < <(grep -vE '^[[:space:]]*(#|$)' "$ALLOW_FILE" 2>/dev/null || true)

# Nothing to strip → exit clean.
if [ "${#PATTERNS[@]}" -eq 0 ]; then
  emit_telemetry "empty-allowlist" 0
  exit 0
fi

# Discover repo root (handles worktrees + bare-repo edge cases).
REPO_ROOT="$(cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || exit 0

# For each pattern, list matching staged paths via `git diff --cached --name-only`.
# Then `git reset HEAD -- <path>` for each. We do NOT use `git restore` because
# we want to preserve the working-tree content (just unstage).
STAGED_FILES="$(cd "$REPO_ROOT" && git diff --cached --name-only 2>/dev/null || true)"
[ -n "$STAGED_FILES" ] || { emit_telemetry "no-staged" 0; exit 0; }

STRIPPED=()
while IFS= read -r path; do
  [ -n "$path" ] || continue
  for pattern in "${PATTERNS[@]}"; do
    pattern="$(printf '%s' "$pattern" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$pattern" ] || continue
    # bash extglob match: enable globstar so ** works
    shopt -s globstar nullglob extglob 2>/dev/null || true
    case "$path" in
      $pattern) STRIPPED+=("$path") ; break ;;
    esac
    shopt -u globstar nullglob extglob 2>/dev/null || true
  done
done <<< "$STAGED_FILES"

if [ "${#STRIPPED[@]}" -eq 0 ]; then
  emit_telemetry "no-match" 0
  exit 0
fi

# Run git reset HEAD -- <each path> from repo root. Use a single command
# with all paths to keep the reflog tidy.
( cd "$REPO_ROOT" && git reset HEAD -- "${STRIPPED[@]}" >/dev/null 2>&1 ) || true

emit_telemetry "stripped" "${#STRIPPED[@]}"
{
  printf '[multi-agent-merge-discipline] stripped %d auto-gen file(s) from staging (will regen post-merge):\n' "${#STRIPPED[@]}"
  for p in "${STRIPPED[@]}"; do printf '  - %s\n' "$p"; done
} >&2

exit 0
