#!/usr/bin/env bash
# audit-gate.sh — Stop hook: advise running /audit when diff exceeds threshold.
#
# Trigger: Stop event (every session end / agent completion).
# Behavior:
#   - Computes `git diff --shortstat` against the merge base of the current branch.
#   - If LOC delta > $GOVERNANCE_PACK_AUDIT_THRESHOLD_LOC (default 50), prints an
#     advisory message to stderr suggesting `/audit`.
#   - ADVISORY ONLY — never blocks. Always exits 0 even on infra failure.
#
# Why advisory: blocking Stop would trap users mid-iteration. The audit decision
# is the user's, not the hook's. Per roadmap-v1.1 §2.3 acceptance crit: "advisory".
#
# Composes with: core-config (this hook never runs PreToolUse, so it does not
# conflict with block-destructive.sh / pre-edit-stash.sh / lint-touched.sh).

set -uo pipefail

# Always exit 0 — we never want to block on Stop.
trap 'exit 0' ERR EXIT

THRESHOLD="${GOVERNANCE_PACK_AUDIT_THRESHOLD_LOC:-50}"

# CLAUDE_PROJECT_DIR is injected by Claude Code when a project is active.
# Fall back to PWD if absent (e.g. global session, no project).
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

cd "$PROJECT_DIR" 2>/dev/null || exit 0

# Skip if not a git repo.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Determine merge base. Try main, master; otherwise stay on HEAD only.
BASE=""
for ref in main master; do
  if git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
    BASE="$ref"
    break
  fi
done

# Sum LOC across three diff scopes (the Stop-hook user has likely got a mix
# of committed, staged, and unstaged work):
#   1. Committed delta vs base branch ($BASE..HEAD)
#   2. Staged changes (HEAD vs index)        — `git diff --cached`
#   3. Unstaged changes (index vs working)   — `git diff` (no args)
sum_loc() {
  # $1 = shortstat output, e.g. " 3 files changed, 42 insertions(+), 7 deletions(-)"
  local s="$1" ins del
  ins=$(echo "$s" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
  del=$(echo "$s" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)
  echo $(( ${ins:-0} + ${del:-0} ))
}

TOTAL=0
SHORTSTAT_PARTS=""

if [ -n "$BASE" ]; then
  S=$(git diff --shortstat "$BASE..HEAD" 2>/dev/null || echo "")
  [ -n "$S" ] && { TOTAL=$((TOTAL + $(sum_loc "$S"))); SHORTSTAT_PARTS="$SHORTSTAT_PARTS  vs $BASE:$S"; }
fi
S=$(git diff --cached --shortstat 2>/dev/null || echo "")
[ -n "$S" ] && { TOTAL=$((TOTAL + $(sum_loc "$S"))); SHORTSTAT_PARTS="$SHORTSTAT_PARTS  staged:$S"; }
S=$(git diff --shortstat 2>/dev/null || echo "")
[ -n "$S" ] && { TOTAL=$((TOTAL + $(sum_loc "$S"))); SHORTSTAT_PARTS="$SHORTSTAT_PARTS  unstaged:$S"; }

# Untracked files: sum line counts so a `Write` to a fresh file is not
# invisible to the gate.
UNTRACKED_LOC=0
while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  n=$(wc -l < "$f" 2>/dev/null || echo 0)
  UNTRACKED_LOC=$(( UNTRACKED_LOC + ${n:-0} ))
done < <(git ls-files --others --exclude-standard -z 2>/dev/null || true)
TOTAL=$((TOTAL + UNTRACKED_LOC))

# Source the shared classifier library (best-effort; absence is non-fatal —
# preserve current advisory behaviour). The library lives next to this hook
# in the source tree and is copied alongside it by install.sh.
CLASSIFY_LIB="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/_lib-audit-classify.sh"
TASK_CLASS="unknown"
AUDIT_ID=""
if [ -f "$CLASSIFY_LIB" ]; then
  # shellcheck disable=SC1090
  . "$CLASSIFY_LIB"
  TASK_CLASS="$(infer_task_class_from_head 2>/dev/null || echo unknown)"
  AUDIT_ID="$(infer_audit_id 2>/dev/null || echo "")"
fi

if [ "$TOTAL" -gt "$THRESHOLD" ]; then
  if [ "$TASK_CLASS" = "feature" ] || [ "$TASK_CLASS" = "system-change" ]; then
    FINDINGS_PATH="docs/sdlc/audit/${AUDIT_ID}-findings.json"
    STATE="missing"
    if [ -n "$AUDIT_ID" ] && [ -f "$FINDINGS_PATH" ]; then
      if command -v jq >/dev/null 2>&1 && jq -e '.verdict == "PASS"' "$FINDINGS_PATH" >/dev/null 2>&1; then
        STATE="present-PASS"
      else
        STATE="present-NOT-PASS"
      fi
    fi
    cat >&2 <<EOF

[governance-pack/audit-gate] Diff: ${TOTAL} LOC; class=${TASK_CLASS}; findings=${STATE}
[governance-pack/audit-gate] Expected artifact: ${FINDINGS_PATH}
[governance-pack/audit-gate]${SHORTSTAT_PARTS}
[governance-pack/audit-gate] To produce: see core/governance-pack/README.md "Producing audit artifacts"
[governance-pack/audit-gate] (advisory only — CI workflow audit-required.yml is the merge gate)

EOF
  else
    cat >&2 <<EOF

[governance-pack/audit-gate] Diff size: ${TOTAL} LOC (threshold: ${THRESHOLD}); class=${TASK_CLASS}
[governance-pack/audit-gate] Audit not required for this task class. Suggest /delta-code-review for triage.
[governance-pack/audit-gate]${SHORTSTAT_PARTS}
[governance-pack/audit-gate] (advisory only — set GOVERNANCE_PACK_AUDIT_THRESHOLD_LOC to tune)

EOF
  fi
fi

exit 0
