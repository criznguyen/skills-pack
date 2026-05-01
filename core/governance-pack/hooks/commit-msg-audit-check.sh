#!/usr/bin/env bash
# commit-msg-audit-check.sh — git commit-msg hook: warn (or BLOCK in strict
# mode) when committing a feature/system-change without a passing audit.
#
# Trigger: git commit-msg (run by `.git/hooks/commit-msg`).
# Git passes the path to the commit-message file as $1; reading $1 yields the
# message being authored RIGHT NOW (correct for `-m`, editor, amend, merge).
#
# History note: this hook was originally registered as `pre-commit` and named
# `pre-commit-audit-check.sh`. That registration was unsound — at pre-commit
# time `.git/COMMIT_EDITMSG` holds the PREVIOUS commit's message (or is empty
# for the first commit), so the hook classified based on stale content. See
# AUDIT-001 in docs/sdlc/audit/audit-builtin-findings.json.
#
# Behaviour:
#   - Reads the commit message being authored from $1 (the path git provides).
#   - Sources `_lib-audit-classify.sh` (next to this file or via
#     $GOVERNANCE_PACK_HOOKS_DIR) for task-class + audit-id inference.
#   - For class ∈ {feature, system-change, forced, unknown}:
#       checks docs/sdlc/audit/<id>-findings.json exists with verdict=PASS.
#   - Default: WARN to stderr, exit 0 (advisory).
#   - With GOVERNANCE_PACK_AUDIT_STRICT=1: exit 1 on missing/non-PASS.
#   - With GOVERNANCE_PACK_AUDIT_DISABLE=1: no-op.
#
# Why advisory by default: this hook ships in core/governance-pack and runs
# on adopter machines; CI workflow `audit-required.yml` is the hard merge
# gate. Local strictness is opt-in — see core/governance-pack/README.md.

set -uo pipefail

if [ "${GOVERNANCE_PACK_AUDIT_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# Locate the classifier library. Three lookup strategies, in order:
#   1. $GOVERNANCE_PACK_HOOKS_DIR (explicit override; used in tests)
#   2. Sibling of this script (when invoked from the install location or repo)
#   3. <repo-root>/core/governance-pack/hooks/ (when this hook is symlinked
#      into .git/hooks from the source tree of claude-skills itself)
SELF_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
CLASSIFY_LIB=""
for candidate in \
  "${GOVERNANCE_PACK_HOOKS_DIR:-}/_lib-audit-classify.sh" \
  "$SELF_DIR/_lib-audit-classify.sh" \
  "$HOME/.claude/hooks/governance-pack/_lib-audit-classify.sh" \
  "$(git rev-parse --show-toplevel 2>/dev/null)/core/governance-pack/hooks/_lib-audit-classify.sh"
do
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    CLASSIFY_LIB="$candidate"
    break
  fi
done

if [ -z "$CLASSIFY_LIB" ]; then
  echo "[commit-msg-audit-check] classifier lib missing — skipping (advisory)" >&2
  exit 0
fi

# shellcheck disable=SC1090
. "$CLASSIFY_LIB"

# Read the commit message being authored. Git passes the path to the message
# file as $1 to commit-msg hooks. For non-`-m` invocations this file holds
# the editor buffer; for `-m` it holds the literal message.
MSG_FILE="${1:-}"
MSG=""
if [ -n "$MSG_FILE" ] && [ -f "$MSG_FILE" ]; then
  MSG="$(cat "$MSG_FILE")"
elif [ -f .git/COMMIT_EDITMSG ] && [ -s .git/COMMIT_EDITMSG ]; then
  # Defensive fallback: hook invoked manually without $1. Read the staging
  # buffer directly. This branch is for testing convenience, not git's
  # native commit-msg invocation.
  MSG="$(cat .git/COMMIT_EDITMSG)"
else
  MSG="$(git log -1 --format=%B HEAD 2>/dev/null || echo "")"
fi

CLASS="$(infer_task_class_from_message "$MSG")"
AUDIT_ID="$(infer_audit_id)"

# Skip path: classes that do not require an audit.
case "$CLASS" in
  bypassed|trivial|small|bug-fix|refactor|docs|test|chore|ci|build|style|perf)
    echo "[commit-msg-audit-check] class=${CLASS} id=${AUDIT_ID} action=SKIP" >&2
    exit 0
    ;;
  feature|system-change|forced|unknown)
    : # fall through to audit enforcement
    ;;
  *)
    # Defensive: any unanticipated token from the lib is treated as fail-closed.
    : # fall through
    ;;
esac

# Audit-required path.
FINDINGS="docs/sdlc/audit/${AUDIT_ID}-findings.json"
STATE="missing"
if [ -f "$FINDINGS" ]; then
  if command -v jq >/dev/null 2>&1; then
    if jq -e '.verdict == "PASS"' "$FINDINGS" >/dev/null 2>&1; then
      STATE="present-PASS"
    else
      STATE="present-BLOCK"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    # Pass the findings path via argv (sys.argv[1]), NOT shell interpolation
    # into the python source. Eliminates the template-injection surface
    # (AUDIT-009) regardless of how $FINDINGS was derived.
    if python3 -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get('verdict')=='PASS' else 1)" "$FINDINGS" 2>/dev/null; then
      STATE="present-PASS"
    else
      STATE="present-BLOCK"
    fi
  else
    # Neither jq nor python3 — cannot parse JSON. Treat as missing (fail-open
    # for WARN, fail-closed only when strict).
    STATE="present-unparseable"
  fi
fi

ACTION="WARN"
if [ "$STATE" = "present-PASS" ]; then
  ACTION="OK"
fi
if [ "${GOVERNANCE_PACK_AUDIT_STRICT:-0}" = "1" ] && [ "$STATE" != "present-PASS" ]; then
  ACTION="BLOCK"
fi

echo "[commit-msg-audit-check] class=${CLASS} id=${AUDIT_ID} findings=${STATE} action=${ACTION}" >&2

if [ "$ACTION" = "BLOCK" ]; then
  cat >&2 <<EOF
[commit-msg-audit-check] BLOCK — set GOVERNANCE_PACK_AUDIT_STRICT=0 to soften,
[commit-msg-audit-check]   or produce ${FINDINGS} with verdict=PASS.
[commit-msg-audit-check] See core/governance-pack/README.md "Producing audit artifacts" for the spawn snippet.
EOF
  exit 1
fi

exit 0
