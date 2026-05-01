#!/usr/bin/env bash
# bash-exitcode.sh — assert tool_response.exit_code == 0.
# match=Bash
# trigger=*
#
# The Gemini-class fabricated-success failure mode: tool returned non-zero
# but the agent narrated success and chained the next step. This is the
# cheapest universal check — it costs nothing and runs on every Bash call.
# Other Bash postconditions (mkdir.sh, git-push.sh, etc.) layer specific
# world-state checks on top.
set -uo pipefail
RC="${CLAUDE_TOOL_EXIT_CODE:-}"
# Empty exit_code (e.g. when the tool surface did not capture it) → skip;
# the hook treats missing data as inconclusive, not as fail.
[ -z "$RC" ] && exit 0
if [ "$RC" != "0" ]; then
  echo "[postcondition bash-exitcode] tool exit_code=$RC (non-zero) — agent must NOT proceed as if successful" >&2
  exit 1
fi
exit 0
