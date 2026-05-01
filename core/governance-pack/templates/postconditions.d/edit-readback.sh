#!/usr/bin/env bash
# edit-readback.sh — assert Edit's target file exists and is non-empty.
# match=Edit
# trigger=*
#
# Best-effort: the hook does not surface the new-content snippet in env
# (architecture §3.1 names CLAUDE_TOOL_INPUT_FILE_PATH only), so the
# verification is "the file exists, is readable, and is non-empty".
# Catches the I-3 Gemini-class fabricated-success on a missing target.
# Operators tightening this for a specific skill add a sibling `.sh`
# with a narrower trigger glob.
set -uo pipefail
F="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"
if [ -z "$F" ]; then
  echo "[postcondition edit-readback] no file_path in tool_input" >&2
  exit 1
fi
if [ ! -f "$F" ]; then
  echo "[postcondition edit-readback] $F does not exist after Edit" >&2
  exit 1
fi
if [ ! -s "$F" ]; then
  echo "[postcondition edit-readback] $F exists but is empty after Edit" >&2
  exit 1
fi
exit 0
