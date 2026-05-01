#!/usr/bin/env bash
# rm.sh — assert removed paths are absent after `rm`.
# match=Bash
# trigger=*rm *
#
# Best-effort: walks tokens after `rm`, skips flags, asserts each
# remaining token is no longer present. Skips when no token survives
# the flag filter (`rm -rf` with no path → already a no-op).
set -uo pipefail
CMD="${CLAUDE_TOOL_INPUT_COMMAND:-}"
case "$CMD" in
  *"rm "*) ;;
  *) exit 0 ;;
esac
# Tolerate quoting / leading flags. Read whitespace-separated tokens.
LINE="$(printf '%s' "$CMD" | tr -s '[:space:]' ' ')"
# Collect non-flag tokens after the literal `rm` keyword.
TARGETS=()
seen_rm=0
for tok in $LINE; do
  if [ "$seen_rm" -eq 0 ]; then
    case "$tok" in
      rm) seen_rm=1 ;;
    esac
    continue
  fi
  case "$tok" in
    -*) continue ;;       # flag
    *) TARGETS+=("$(printf '%s' "$tok" | tr -d "'\"")") ;;
  esac
done
[ "${#TARGETS[@]}" -eq 0 ] && exit 0
for t in "${TARGETS[@]}"; do
  if [ -e "$t" ] || [ -L "$t" ]; then
    echo "[postcondition rm] $t still present after rm" >&2
    exit 1
  fi
done
exit 0
