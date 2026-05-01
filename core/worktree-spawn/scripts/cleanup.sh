#!/usr/bin/env bash
# cleanup.sh — safely remove a worktree (refuses if uncommitted work present).
#
# Usage: cleanup.sh <branch-or-path> [--force] [--keep-branch]
#
#   <branch-or-path>   either a branch name (e.g. wt/foo-1) or a worktree path
#                      (e.g. .worktrees/foo-1). The path form must match an
#                      existing entry in `git worktree list`.
#   --force            remove despite uncommitted changes (logs a warning)
#   --keep-branch      remove the worktree but keep the local branch
#
# Refuses by default if:
#   - `git status --porcelain` non-empty (untracked + modified + staged)
#   - branch has unmerged commits relative to its merge-base with main
#
# Exit codes:
#   0  removed
#   2  bad args / not found
#   3  refused (uncommitted or unmerged); use --force to override
#   4  underlying git failure
#
# Per roadmap §2.4 acceptance: cleanup must not destroy uncommitted work.

set -euo pipefail

FORCE=0
KEEP_BRANCH=0
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)        FORCE=1; shift ;;
    --keep-branch)  KEEP_BRANCH=1; shift ;;
    -h|--help)      sed -n '2,22p' "$0"; exit 0 ;;
    --)             shift; break ;;
    -*)             echo "cleanup.sh: unknown flag: $1" >&2; exit 2 ;;
    *)              if [[ -z "$TARGET" ]]; then TARGET="$1"; shift
                    else echo "cleanup.sh: extra arg: $1" >&2; exit 2; fi ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "cleanup.sh: <branch-or-path> required" >&2
  echo "usage: cleanup.sh <branch-or-path> [--force] [--keep-branch]" >&2
  exit 2
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "cleanup.sh: not inside a git repository" >&2
  exit 2
fi

cd "$(git rev-parse --show-toplevel)"

# ---- resolve TARGET to (path, branch) ----
WT_PATH=""
WT_BRANCH=""

# Try as path first.
if [[ -e "$TARGET" ]]; then
  ABS_TARGET="$(cd "$TARGET" 2>/dev/null && pwd || true)"
  cur_path=""; cur_branch=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) cur_path="${line#worktree }" ;;
      branch\ *)   cur_branch="${line#branch }" ;;
      "")
        if [[ "$cur_path" == "$ABS_TARGET" ]]; then
          WT_PATH="$cur_path"
          WT_BRANCH="${cur_branch#refs/heads/}"
          break
        fi
        cur_path=""; cur_branch="" ;;
    esac
  done < <(git worktree list --porcelain; echo "")
fi

# Try as branch.
if [[ -z "$WT_PATH" ]]; then
  cur_path=""; cur_branch=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) cur_path="${line#worktree }" ;;
      branch\ *)   cur_branch="${line#branch }" ;;
      "")
        if [[ "${cur_branch#refs/heads/}" == "$TARGET" ]]; then
          WT_PATH="$cur_path"
          WT_BRANCH="${cur_branch#refs/heads/}"
          break
        fi
        cur_path=""; cur_branch="" ;;
    esac
  done < <(git worktree list --porcelain; echo "")
fi

if [[ -z "$WT_PATH" ]]; then
  echo "cleanup.sh: no worktree matches '$TARGET'" >&2
  echo "  list active worktrees with: scripts/list.sh" >&2
  exit 2
fi

# Refuse to remove the main checkout.
MAIN_TOPLEVEL="$(git rev-parse --show-toplevel)"
if [[ "$WT_PATH" == "$MAIN_TOPLEVEL" ]]; then
  echo "cleanup.sh: refusing to remove the main checkout ($WT_PATH)" >&2
  exit 2
fi

# ---- safety checks ----
DIRTY="$(git -C "$WT_PATH" status --porcelain 2>/dev/null || true)"
UNMERGED=""
if [[ -n "$WT_BRANCH" ]] && git show-ref --verify --quiet "refs/heads/$WT_BRANCH"; then
  # Pick a sensible base: prefer 'main', else 'master', else the worktree's upstream.
  BASE_REF=""
  for cand in main master; do
    if git show-ref --verify --quiet "refs/heads/$cand"; then BASE_REF="$cand"; break; fi
  done
  if [[ -z "$BASE_REF" ]]; then
    BASE_REF="$(git rev-parse --abbrev-ref --symbolic-full-name "${WT_BRANCH}@{u}" 2>/dev/null || true)"
  fi
  if [[ -n "$BASE_REF" ]]; then
    UNMERGED="$(git log --oneline "${BASE_REF}..${WT_BRANCH}" 2>/dev/null || true)"
  fi
fi

if [[ -n "$DIRTY" || -n "$UNMERGED" ]]; then
  echo "cleanup.sh: worktree has work that would be lost"
  echo "  path:   $WT_PATH"
  echo "  branch: ${WT_BRANCH:-<detached>}"
  if [[ -n "$DIRTY" ]]; then
    echo "  --- uncommitted (git status --porcelain) ---"
    printf '%s\n' "$DIRTY" | sed 's/^/    /'
  fi
  if [[ -n "$UNMERGED" ]]; then
    echo "  --- unmerged commits (vs ${BASE_REF:-base}) ---"
    printf '%s\n' "$UNMERGED" | sed 's/^/    /'
  fi
  if [[ "$FORCE" -ne 1 ]]; then
    echo "  refused — pass --force to override (you will lose this work)"
    exit 3
  fi
  echo "  --force given — proceeding anyway. WARNING: work above will be lost."
fi

# ---- remove ----
RM_FLAGS=()
[[ "$FORCE" -eq 1 ]] && RM_FLAGS+=(--force)

if ! git worktree remove "${RM_FLAGS[@]}" "$WT_PATH"; then
  echo "cleanup.sh: git worktree remove failed for $WT_PATH" >&2
  exit 4
fi

if [[ -n "$WT_BRANCH" && "$KEEP_BRANCH" -ne 1 ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    git branch -D "$WT_BRANCH" >/dev/null 2>&1 || true
  else
    git branch -d "$WT_BRANCH" >/dev/null 2>&1 || true
  fi
fi

git worktree prune >/dev/null 2>&1 || true

echo "cleanup.sh: removed worktree $WT_PATH${WT_BRANCH:+ (branch $WT_BRANCH)}"
