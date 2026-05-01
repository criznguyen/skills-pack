#!/usr/bin/env bash
# list.sh — ps-equivalent for worktrees: branch, path, dirty?, unmerged?, age
#
# Usage: list.sh [--json]
#
# Columns: branch | path | dirty | unmerged-vs-main | age
#
# Per roadmap §2.4 — operators need a quick "what's in flight" view to
# decide whether to merge/cleanup before spawning more.

set -euo pipefail

JSON=0
case "${1:-}" in
  --json) JSON=1 ;;
  -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
  "") ;;
  *) echo "list.sh: unknown arg: $1" >&2; exit 2 ;;
esac

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "list.sh: not inside a git repository" >&2
  exit 2
fi
cd "$(git rev-parse --show-toplevel)"

# pick base ref
BASE_REF=""
for cand in main master; do
  if git show-ref --verify --quiet "refs/heads/$cand"; then BASE_REF="$cand"; break; fi
done

MAIN_TOPLEVEL="$(git rev-parse --show-toplevel)"

declare -a ROWS=()
cur_path=""; cur_branch=""

while IFS= read -r line; do
  case "$line" in
    worktree\ *) cur_path="${line#worktree }" ;;
    branch\ *)   cur_branch="${line#branch }" ;;
    "")
      if [[ -z "$cur_path" ]]; then continue; fi
      if [[ "$cur_path" == "$MAIN_TOPLEVEL" ]]; then
        cur_path=""; cur_branch=""; continue
      fi
      br="${cur_branch#refs/heads/}"
      [[ -z "$br" ]] && br="(detached)"

      dirty="clean"
      if [[ -d "$cur_path" ]]; then
        if [[ -n "$(git -C "$cur_path" status --porcelain 2>/dev/null || true)" ]]; then
          dirty="DIRTY"
        fi
      else
        dirty="MISSING"
      fi

      unmerged="-"
      if [[ -n "$BASE_REF" && "$br" != "(detached)" ]] && \
         git show-ref --verify --quiet "refs/heads/$br"; then
        n="$(git rev-list --count "${BASE_REF}..${br}" 2>/dev/null || echo 0)"
        if [[ "$n" -gt 0 ]]; then unmerged="${n} ahead"; else unmerged="merged"; fi
      fi

      age="-"
      if [[ "$br" != "(detached)" ]] && git show-ref --verify --quiet "refs/heads/$br"; then
        ts="$(git log -1 --format=%ct "$br" 2>/dev/null || echo 0)"
        if [[ "$ts" -gt 0 ]]; then
          now="$(date +%s)"
          delta=$(( now - ts ))
          if   (( delta < 3600 ));   then age="$(( delta / 60 ))m"
          elif (( delta < 86400 ));  then age="$(( delta / 3600 ))h"
          else                            age="$(( delta / 86400 ))d"
          fi
        fi
      fi

      ROWS+=("${br}|${cur_path}|${dirty}|${unmerged}|${age}")
      cur_path=""; cur_branch=""
      ;;
  esac
done < <(git worktree list --porcelain; echo "")

CAP="${WT_CAP:-3}"
COUNT="${#ROWS[@]}"

if [[ "$JSON" -eq 1 ]]; then
  printf '{\n  "cap": %s,\n  "count": %s,\n  "worktrees": [\n' "$CAP" "$COUNT"
  for ((i = 0; i < COUNT; i++)); do
    IFS='|' read -r br p d u a <<<"${ROWS[$i]}"
    sep=","; (( i == COUNT - 1 )) && sep=""
    printf '    {"branch": "%s", "path": "%s", "dirty": "%s", "unmerged": "%s", "age": "%s"}%s\n' \
      "$br" "$p" "$d" "$u" "$a" "$sep"
  done
  printf '  ]\n}\n'
  exit 0
fi

printf '%-28s  %-40s  %-7s  %-12s  %s\n' "BRANCH" "PATH" "STATE" "VS-${BASE_REF:-base}" "AGE"
printf '%-28s  %-40s  %-7s  %-12s  %s\n' "----------------------------" "----------------------------------------" "-------" "------------" "---"
if (( COUNT == 0 )); then
  echo "(no spawned worktrees — only the main checkout exists)"
else
  for row in "${ROWS[@]}"; do
    IFS='|' read -r br p d u a <<<"$row"
    printf '%-28s  %-40s  %-7s  %-12s  %s\n' "$br" "$p" "$d" "$u" "$a"
  done
fi
echo
echo "cap: ${COUNT} / ${CAP} active spawned worktrees"
