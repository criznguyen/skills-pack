#!/usr/bin/env bash
# spawn.sh — create up to 3 git worktrees with auto-generated coordination CLAUDE.md
#
# Usage: spawn.sh <task-id> [N=2] [--scope "what each worktree is for"]
#
# Env overrides:
#   WT_BRANCH_PREFIX      branch prefix (default: wt/)
#   WT_ROOT               worktree root dir (default: .worktrees)
#   WT_CAP                hard cap (default: 3; do NOT raise without reading CAVEAT.md)
#   WT_BASE_REF           base ref for new branches (default: HEAD of current branch)
#
# Exit codes:
#   0  success
#   2  bad args / repo not found
#   3  cap reached or would exceed cap
#   4  branch/dir collision
#
# Per roadmap §2.4 (P0-04). Cap rationale lives in CAVEAT.md and README.md.

set -euo pipefail

WT_BRANCH_PREFIX="${WT_BRANCH_PREFIX:-wt/}"
WT_ROOT="${WT_ROOT:-.worktrees}"
WT_CAP="${WT_CAP:-3}"
WT_BASE_REF="${WT_BASE_REF:-HEAD}"

# ---- arg parsing ----
TASK_ID=""
N=2
SCOPE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      SCOPE="${2:-}"; shift 2 ;;
    --scope=*)
      SCOPE="${1#--scope=}"; shift ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    --)
      shift; break ;;
    -*)
      echo "spawn.sh: unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$TASK_ID" ]]; then
        TASK_ID="$1"
      elif [[ "$1" =~ ^[0-9]+$ ]]; then
        N="$1"
      else
        echo "spawn.sh: unexpected positional arg: $1" >&2; exit 2
      fi
      shift ;;
  esac
done

if [[ -z "$TASK_ID" ]]; then
  echo "spawn.sh: <task-id> required" >&2
  echo "usage: spawn.sh <task-id> [N=2] [--scope \"...\"]" >&2
  exit 2
fi

# ---- repo sanity ----
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "spawn.sh: not inside a git repository" >&2
  exit 2
fi

REPO_TOPLEVEL="$(git rev-parse --show-toplevel)"
cd "$REPO_TOPLEVEL"

# ---- cap enforcement ----
# git worktree list includes the main checkout; subtract 1 for it.
EXISTING_TOTAL=$(git worktree list --porcelain | grep -c '^worktree ' || true)
EXISTING_SPAWNED=$(( EXISTING_TOTAL - 1 ))
[[ "$EXISTING_SPAWNED" -lt 0 ]] && EXISTING_SPAWNED=0

if [[ "$N" -lt 1 ]]; then
  echo "spawn.sh: N must be >= 1 (got $N)" >&2
  exit 2
fi

PROJECTED=$(( EXISTING_SPAWNED + N ))
if [[ "$PROJECTED" -gt "$WT_CAP" ]]; then
  cat >&2 <<EOF
spawn.sh: cap reached; merge or delete one before spawning more
  current spawned worktrees: $EXISTING_SPAWNED
  requested:                 $N
  cap (WT_CAP):              $WT_CAP
  projected:                 $PROJECTED

v1 caps parallel worktrees at 3. See:
  - core/worktree-spawn/CAVEAT.md  (when 1 beats N, when N beats 1)
  - docs/synthesis/v1.1/charter-v1.1.md §6 (merge-wall caveat)

To inspect existing worktrees: scripts/list.sh
To remove one cleanly:         scripts/cleanup.sh <branch-or-path>
EOF
  exit 3
fi

# ---- compute next sequence numbers ----
# A branch is "ours" if it matches "<prefix><task-id>-<digits>".
SAFE_TASK_ID="${TASK_ID//[^A-Za-z0-9_-]/-}"
PREFIX_FULL="${WT_BRANCH_PREFIX}${SAFE_TASK_ID}-"

MAX_SEQ=0
while IFS= read -r br; do
  [[ -z "$br" ]] && continue
  seq="${br#"$PREFIX_FULL"}"
  if [[ "$seq" =~ ^[0-9]+$ ]] && (( seq > MAX_SEQ )); then
    MAX_SEQ="$seq"
  fi
done < <(git for-each-ref --format='%(refname:short)' "refs/heads/${PREFIX_FULL}*" 2>/dev/null || true)

# ---- plan the spawn ----
declare -a BRANCHES=()
declare -a PATHS=()
for ((i = 1; i <= N; i++)); do
  next=$(( MAX_SEQ + i ))
  br="${PREFIX_FULL}${next}"
  wp="${WT_ROOT}/${SAFE_TASK_ID}-${next}"
  if git show-ref --verify --quiet "refs/heads/${br}"; then
    echo "spawn.sh: branch already exists: $br" >&2
    exit 4
  fi
  if [[ -e "$wp" ]]; then
    echo "spawn.sh: path already exists: $wp" >&2
    exit 4
  fi
  BRANCHES+=("$br")
  PATHS+=("$wp")
done

mkdir -p "$WT_ROOT"

# ---- create worktrees ----
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" && pwd)"
COORD_TEMPLATE="${TEMPLATE_DIR}/coordination-CLAUDE.md"
CHARTER_TEMPLATE="${TEMPLATE_DIR}/feature-charter.md"

if [[ ! -f "$COORD_TEMPLATE" ]]; then
  echo "spawn.sh: coordination template missing at $COORD_TEMPLATE" >&2
  exit 2
fi

CREATED=()
SPAWN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SUPERVISOR="${USER:-unknown}"

cleanup_partial() {
  local code=$?
  if (( ${#CREATED[@]} > 0 )); then
    echo "spawn.sh: spawn failed mid-run; rolling back ${#CREATED[@]} partial worktree(s)" >&2
    for entry in "${CREATED[@]}"; do
      p="${entry%%::*}"
      b="${entry##*::}"
      git worktree remove --force "$p" >/dev/null 2>&1 || true
      git branch -D "$b" >/dev/null 2>&1 || true
    done
  fi
  exit "$code"
}
trap cleanup_partial ERR

for ((i = 0; i < N; i++)); do
  br="${BRANCHES[$i]}"
  wp="${PATHS[$i]}"
  git worktree add -b "$br" "$wp" "$WT_BASE_REF" >/dev/null
  CREATED+=("${wp}::${br}")
done

trap - ERR

# ---- siblings list (each worktree learns about ALL siblings) ----
sibling_block() {
  local self_idx="$1"
  local out=""
  for ((j = 0; j < N; j++)); do
    if (( j == self_idx )); then continue; fi
    out+="- \`${BRANCHES[$j]}\` at \`${PATHS[$j]}\`"$'\n'
  done
  if [[ -z "$out" ]]; then
    out="(none — this is a solo worktree)"$'\n'
  fi
  printf '%s' "$out"
}

# ---- merge-order recommendation (smallest seq first; user can override) ----
merge_order_block() {
  local out=""
  for ((j = 0; j < N; j++)); do
    out+="${j}. \`${BRANCHES[$j]}\`"$'\n'
  done
  printf '%s' "$out"
}

render_template() {
  local template_path="$1"
  local self_idx="$2"
  local self_branch="${BRANCHES[$self_idx]}"
  local self_path="${PATHS[$self_idx]}"
  local self_n=$(( self_idx + 1 ))
  local total="$N"
  local siblings; siblings="$(sibling_block "$self_idx")"
  local merge_order; merge_order="$(merge_order_block)"

  python3 - "$template_path" <<PY
import os, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    body = f.read()
subs = {
    "TASK_ID":       os.environ["TASK_ID"],
    "SCOPE":         os.environ["SCOPE"],
    "BRANCH":        os.environ["BRANCH"],
    "WORKTREE_PATH": os.environ["WORKTREE_PATH"],
    "WORKTREE_N":    os.environ["WORKTREE_N"],
    "WORKTREE_TOTAL":os.environ["WORKTREE_TOTAL"],
    "BASE_REF":      os.environ["BASE_REF"],
    "SPAWN_TS":      os.environ["SPAWN_TS"],
    "SUPERVISOR":    os.environ["SUPERVISOR"],
    "SIBLINGS":      os.environ["SIBLINGS"],
    "MERGE_ORDER":   os.environ["MERGE_ORDER"],
    "CAP":           os.environ["CAP"],
}
for k, v in subs.items():
    body = body.replace("{{" + k + "}}", v)
sys.stdout.write(body)
PY
}

for ((i = 0; i < N; i++)); do
  br="${BRANCHES[$i]}"
  wp="${PATHS[$i]}"

  # Add coordination files to the worktree-local exclude so they don't
  # show up in `git status` (and thus don't trip cleanup.sh's dirty-check
  # for an unused worktree). The path resolves per-worktree.
  excl_file="$(git -C "$wp" rev-parse --git-path info/exclude 2>/dev/null || echo)"
  if [[ -n "$excl_file" ]]; then
    mkdir -p "$(dirname "$excl_file")"
    {
      echo "# added by core/worktree-spawn/scripts/spawn.sh"
      echo "/CLAUDE.md"
      echo "/FEATURE-CHARTER.md"
      echo "/BLOCKERS.md"
    } >> "$excl_file"
  fi

  TASK_ID="$TASK_ID" \
  SCOPE="${SCOPE:-(scope not provided — fill in feature-charter.md)}" \
  BRANCH="$br" \
  WORKTREE_PATH="$wp" \
  WORKTREE_N="$(( i + 1 ))" \
  WORKTREE_TOTAL="$N" \
  BASE_REF="$WT_BASE_REF" \
  SPAWN_TS="$SPAWN_TS" \
  SUPERVISOR="$SUPERVISOR" \
  SIBLINGS="$(sibling_block "$i")" \
  MERGE_ORDER="$(merge_order_block)" \
  CAP="$WT_CAP" \
  render_template "$COORD_TEMPLATE" "$i" > "${wp}/CLAUDE.md"

  TASK_ID="$TASK_ID" \
  SCOPE="${SCOPE:-(scope not provided — fill in this file)}" \
  BRANCH="$br" \
  WORKTREE_PATH="$wp" \
  WORKTREE_N="$(( i + 1 ))" \
  WORKTREE_TOTAL="$N" \
  BASE_REF="$WT_BASE_REF" \
  SPAWN_TS="$SPAWN_TS" \
  SUPERVISOR="$SUPERVISOR" \
  SIBLINGS="$(sibling_block "$i")" \
  MERGE_ORDER="$(merge_order_block)" \
  CAP="$WT_CAP" \
  render_template "$CHARTER_TEMPLATE" "$i" > "${wp}/FEATURE-CHARTER.md"
done

# ---- summary ----
echo
echo "Spawned $N worktree(s) for task: $TASK_ID"
for ((i = 0; i < N; i++)); do
  echo "  [$((i+1))/$N] ${BRANCHES[$i]}  ->  ${PATHS[$i]}"
done
cat <<EOF

Coordination files written to each worktree:
  - CLAUDE.md            (sibling list, scope, merge order)
  - FEATURE-CHARTER.md   (working scope; fill before starting work)

Merge-wall caveat (Steve Yegge): cross-worktree dependencies surface at merge,
not during work. Above 3 parallel worktrees, the supervisor's own context budget
becomes the bottleneck. See CAVEAT.md.

Recommended merge order (override if dependency graph differs):
$(merge_order_block)
Cap status: $((EXISTING_SPAWNED + N)) / $WT_CAP active spawned worktrees.
EOF
