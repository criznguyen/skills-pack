#!/usr/bin/env bash
# mkdir.sh — assert mkdir target directory now exists.
# match=Bash
# trigger=*mkdir*
#
# Defends against the I-3 Gemini-CLI failure: agent ran `mkdir foo`,
# hook surface returned non-zero, agent narrated success and chained
# Windows `move` over user files. This postcondition extracts the
# last-token directory argument and asserts `[ -d ... ]`. Heuristic;
# does not parse `mkdir -p a/b/c -- d/e/f` perfectly. Operators with
# more complex mkdir invocations add a sibling `.sh` with a tighter
# trigger glob.
set -uo pipefail
CMD="${CLAUDE_TOOL_INPUT_COMMAND:-}"
[ -z "$CMD" ] && exit 0
case "$CMD" in
  *mkdir*) ;;
  *) exit 0 ;;
esac
# Last token is usually the path. Tolerant of `-p` / `-m 0755` / quotes.
DST="$(printf '%s' "$CMD" | awk '{print $NF}' | tr -d "'\"")"
[ -z "$DST" ] && exit 0
if [ ! -d "$DST" ]; then
  echo "[postcondition mkdir] dst=$DST does not exist after mkdir — agent must NOT claim success" >&2
  exit 1
fi
exit 0
