#!/usr/bin/env bash
# write-stat.sh — assert Write's target file exists and is non-empty.
# match=Write
# trigger=*
#
# Symmetric to edit-readback.sh but on the Write tool. Catches the
# fabricated-success failure mode where the agent claims a file
# was created but the tool actually failed (e.g. permission denied,
# disk full, parent missing).
set -uo pipefail
F="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"
if [ -z "$F" ]; then
  echo "[postcondition write-stat] no file_path in tool_input" >&2
  exit 1
fi
if [ ! -f "$F" ]; then
  echo "[postcondition write-stat] $F does not exist after Write" >&2
  exit 1
fi
if [ ! -s "$F" ]; then
  echo "[postcondition write-stat] $F exists but is empty after Write" >&2
  exit 1
fi
exit 0
