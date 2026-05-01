#!/usr/bin/env bash
# git-push.sh — assert local HEAD reached the upstream after `git push`.
# match=Bash
# trigger=*git push*
#
# Local fetch + compare upstream tip vs local HEAD. The single network
# call is bounded by the hook's 5s timeout (TM3); operators on slow
# networks override per-postcondition via `# timeout_override=10`.
# Catches the I-1 Replit-class fabricated rollback report: agent
# narrated "pushed and verified" but push failed silently.
set -uo pipefail
CMD="${CLAUDE_TOOL_INPUT_COMMAND:-}"
case "$CMD" in
  *"git push"*) ;;
  *) exit 0 ;;
esac
# Fetch the tracked upstream silently. If no upstream is configured this
# postcondition has nothing to verify and skips.
git fetch --quiet >/dev/null 2>&1 || {
  echo "[postcondition git-push] git fetch failed — cannot verify push reached upstream" >&2
  exit 1
}
LOCAL="$(git rev-parse HEAD 2>/dev/null || echo)"
UPSTREAM="$(git rev-parse '@{u}' 2>/dev/null || echo)"
if [ -z "$UPSTREAM" ]; then
  # No tracked upstream — nothing to compare. Silent skip.
  exit 0
fi
if [ "$LOCAL" != "$UPSTREAM" ]; then
  echo "[postcondition git-push] local HEAD=$LOCAL ≠ upstream=$UPSTREAM — push did not land" >&2
  exit 1
fi
exit 0
