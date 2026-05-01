#!/usr/bin/env bash
# npm-install.sh — assert node_modules/ now exists after `npm i` / `npm install`.
# match=Bash
# trigger=*npm i*
#
# Heuristic: `npm install` (and short form `npm i`) creates / updates
# `node_modules/`. The check is "directory exists and is non-empty".
# Adopters using yarn/pnpm/bun add their own siblings; this default
# only covers npm. Operators tightening for a specific package add
# a sibling `.sh` checking `node_modules/<pkg>/package.json`.
set -uo pipefail
CMD="${CLAUDE_TOOL_INPUT_COMMAND:-}"
case "$CMD" in
  *"npm install"*|*"npm i "*|*"npm i") ;;
  *) exit 0 ;;
esac
# Where was the command run? CLAUDE_PROJECT_DIR if available, else PWD.
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
NM="$DIR/node_modules"
if [ ! -d "$NM" ]; then
  echo "[postcondition npm-install] $NM missing — npm install did not produce node_modules" >&2
  exit 1
fi
# Empty node_modules is suspicious (install failed mid-flight).
if ! ls -A "$NM" >/dev/null 2>&1; then
  echo "[postcondition npm-install] $NM exists but is empty" >&2
  exit 1
fi
exit 0
