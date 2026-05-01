#!/usr/bin/env bash
# mv.sh — assert dst exists and src no longer exists after `mv`.
# match=Bash
# trigger=*mv *
#
# Best-effort: parses the LAST two whitespace-separated tokens as
# `mv ... SRC DST`. Tolerant of `mv -f` / `mv -v` / quoted args; will
# misfire on `mv` with multiple sources (`mv a b c targetdir/`) — for
# those, operators add a tighter sibling `.sh`. Heuristic.
set -uo pipefail
CMD="${CLAUDE_TOOL_INPUT_COMMAND:-}"
case "$CMD" in
  *"mv "*) ;;
  *) exit 0 ;;
esac
# Drop trailing newline, then collapse whitespace so awk can split.
LINE="$(printf '%s' "$CMD" | tr -s '[:space:]' ' ')"
N="$(printf '%s' "$LINE" | awk '{print NF}')"
[ "${N:-0}" -lt 3 ] && exit 0  # need at least `mv SRC DST`
SRC="$(printf '%s' "$LINE" | awk '{print $(NF-1)}' | tr -d "'\"")"
DST="$(printf '%s' "$LINE" | awk '{print $NF}'    | tr -d "'\"")"
# Multi-source heuristic: if DST looks like an existing directory the
# move could have any number of sources — skip.
if [ -d "$DST" ] && [ "${N}" -gt 3 ]; then
  exit 0
fi
if [ ! -e "$DST" ]; then
  echo "[postcondition mv] dst=$DST missing after mv" >&2
  exit 1
fi
if [ -e "$SRC" ]; then
  echo "[postcondition mv] src=$SRC still present after mv (overwrite or no-op?)" >&2
  exit 1
fi
exit 0
