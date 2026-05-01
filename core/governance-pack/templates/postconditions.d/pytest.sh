#!/usr/bin/env bash
# pytest.sh — assert pytest output contains a "passed" line.
# match=Bash
# trigger=*pytest*
# verify_substring=passed
#
# Catches the failure mode where the agent claims tests pass but the
# actual run errored or no tests were collected. Reads the captured
# tool stdout file (when the hook-stdin payload provided one) and
# greps for the literal "passed" — the standard pytest summary line
# shape (e.g. "5 passed in 0.12s"). On runs where pytest captured
# stdout differently (CI redactors / pytest-xdist) the verify_substring
# assertion in the hook handles the check; this body is a redundant
# guard with a clearer error message.
set -uo pipefail
F="${CLAUDE_TOOL_STDOUT_FILE:-}"
[ -z "$F" ] && exit 0  # no captured stdout — skip; bash-exitcode.sh covers the rc=0 path
[ -f "$F" ] || exit 0
if ! grep -q "passed" "$F"; then
  TAIL="$(tail -c 200 "$F" 2>/dev/null | tr -d '\n' || true)"
  echo "[postcondition pytest] no 'passed' line in tool stdout (tail=${TAIL})" >&2
  exit 1
fi
exit 0
