#!/usr/bin/env bash
# init-repo.sh — create a minimal throwaway git repo for worktree-spawn tests.
#
# Usage: init-repo.sh <target-dir>
#   <target-dir>  empty (or non-existent) directory to populate.
#
# Produces a repo with:
#   - main branch with one commit
#   - a tiny README.md so HEAD has content
#   - git user.email/user.name configured locally so commits work in CI
#
# Idempotent: if <target-dir> already contains a valid git repo, exits 0.

set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "init-repo.sh: <target-dir> required" >&2
  exit 2
fi

mkdir -p "$TARGET"
cd "$TARGET"

if git rev-parse --git-dir >/dev/null 2>&1 && [[ -n "$(git log --oneline 2>/dev/null || true)" ]]; then
  exit 0
fi

git init -q -b main
git config user.email "fixture@example.invalid"
git config user.name  "worktree-spawn fixture"
git config commit.gpgsign false 2>/dev/null || true
git config tag.gpgsign    false 2>/dev/null || true

cat > README.md <<EOF
# fixture repo

Throwaway repo used by core/worktree-spawn tests. Do not depend on its history.
EOF

git add README.md
git commit -q -m "init: fixture repo"
