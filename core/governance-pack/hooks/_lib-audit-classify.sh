#!/usr/bin/env bash
# _lib-audit-classify.sh — shared task-class + audit-id inference for governance-pack.
#
# Sourced by:
#   - hooks/audit-gate.sh             (Stop hook, advisory)
#   - hooks/commit-msg-audit-check.sh (git commit-msg, advisory by default)
#   - .github/workflows/audit-required.yml (sourced inline by CI)
#
# DO NOT execute directly. Functions echo a single token to stdout and never
# call exit. Callers decide fail-open vs fail-closed semantics on `unknown`.
#
# Single source of truth for the conventional-commits → task-class projection
# (charter v1.1 §3 task-class rubric, operationalised). Keep the case statement
# in `infer_task_class_from_message` aligned with:
#   - docs/sdlc/tech-spec/audit-builtin.md §2 (canonical map)
#   - core/governance-pack/README.md "Conventional-commits map"

# infer_task_class_from_message <commit-message-string>
#
# Echoes one token to stdout:
#   trivial small bug-fix feature system-change refactor docs chore test
#   ci build style perf bypassed forced unknown
#
# Precedence (first match wins):
#   1. Footer overrides ([skip audit] / Audit-Skip:, [force audit] / Audit-Required: yes)
#   2. Conventional-commits prefix on the subject (first non-empty line)
#   3. unknown — caller decides fail-open vs fail-closed
infer_task_class_from_message() {
  local msg="${1:-}"

  # 1. Footer overrides — match anywhere in the message body.
  if printf '%s\n' "$msg" | grep -qE '^\[skip audit\]$|^Audit-Skip:[[:space:]]*.+$'; then
    echo "bypassed"; return
  fi
  if printf '%s\n' "$msg" | grep -qE '^\[force audit\]$|^Audit-Required:[[:space:]]*yes$'; then
    echo "forced"; return
  fi

  # 2. Conventional-commits prefix on subject (first non-empty line).
  local subj
  subj="$(printf '%s\n' "$msg" | awk 'NF{print;exit}')"
  case "$subj" in
    "feat!:"*|"feature!:"*)                        echo "system-change"; return;;
    "fix!:"*|"refactor!:"*|"perf!:"*)              echo "system-change"; return;;
    "feat("*"!:"*|"feature("*"!:"*)                echo "system-change"; return;;
    "fix("*"!:"*|"refactor("*"!:"*|"perf("*"!:"*)  echo "system-change"; return;;
    "feat:"*|"feat("*)                             echo "feature"; return;;
    "feature:"*|"feature("*)                       echo "feature"; return;;
    "fix:"*|"fix("*)                               echo "bug-fix"; return;;
    "bugfix:"*|"hotfix:"*)                         echo "bug-fix"; return;;
    "refactor:"*|"refactor("*)                     echo "refactor"; return;;
    "docs:"*|"docs("*)                             echo "docs"; return;;
    "test:"*|"test("*|"tests:"*|"tests("*)         echo "test"; return;;
    "chore:"*|"chore("*)                           echo "chore"; return;;
    "ci:"*|"ci("*)                                 echo "ci"; return;;
    "build:"*|"build("*)                           echo "build"; return;;
    "style:"*|"style("*)                           echo "style"; return;;
    "perf:"*|"perf("*)                             echo "perf"; return;;
  esac

  # 3. No recognized prefix — caller decides.
  echo "unknown"
}

# infer_task_class_from_head — convenience wrapper: reads HEAD commit message.
# Echoes "unknown" if not in a git repo or HEAD has no commit.
infer_task_class_from_head() {
  local msg
  msg="$(git log -1 --format=%B HEAD 2>/dev/null || echo "")"
  if [ -z "$msg" ]; then
    echo "unknown"
    return
  fi
  infer_task_class_from_message "$msg"
}

# _audit_id_pattern_ok — return 0 iff $1 matches report.json id pattern.
_audit_id_pattern_ok() {
  printf '%s' "${1:-}" | grep -qE '^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$'
}

# _audit_id_branch_slug — derive a sluggified branch name on stdout.
# Strips known prefixes, lowercases, replaces non-[a-z0-9-] with '-', trims.
_audit_id_branch_slug() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    return 1
  fi
  printf '%s' "$branch" \
    | sed -E 's#^(feat|feature|system|breaking|fix|hotfix|bugfix|refactor|docs|chore|test|ci|build|style|perf)/##' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#[^a-z0-9-]#-#g; s#^-+##; s#-+$##' \
    | cut -c1-63
}

# infer_audit_id — echoes the canonical audit-id for the current task.
#
# Precedence (first match wins) — operationalises architecture §3.2:
#   1. Env var $AUDIT_ID, if it matches the report.json id pattern.
#   2. Branch `<prefix>/<slug>` where docs/sdlc/spec/<slug>.md exists.
#   3. Single matching spec — when exactly one .md basename in docs/sdlc/spec/
#      matches the id pattern, use that basename.
#   4. Multiple specs disambiguated by spec title — read the first H1 (line 1
#      of `# Spec — \`<id>\``); if exactly one spec's title matches the branch
#      slug, use it.
#   5. Fallback: branch-slug + short-SHA (audit-<slug>-<sha>) so a fresh branch
#      with no spec yet still produces a deterministic id.
#
# All emitted values are validated against `^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$`.
infer_audit_id() {
  local env_id slug spec_path spec_id sha matches=()

  # 1. Explicit env override.
  env_id="${AUDIT_ID:-}"
  if [ -n "$env_id" ] && _audit_id_pattern_ok "$env_id"; then
    echo "$env_id"
    return
  fi

  # Compute branch slug once; reused below.
  slug="$(_audit_id_branch_slug 2>/dev/null || echo "")"

  # 2. Branch slug + matching spec file.
  if [ -n "$slug" ] && [ -f "docs/sdlc/spec/${slug}.md" ] \
      && _audit_id_pattern_ok "$slug"; then
    echo "$slug"
    return
  fi

  # 3. Single matching spec.
  if [ -d "docs/sdlc/spec" ]; then
    for spec_path in docs/sdlc/spec/*.md; do
      [ -f "$spec_path" ] || continue
      spec_id="$(basename "$spec_path" .md)"
      if _audit_id_pattern_ok "$spec_id"; then
        matches+=("$spec_id")
      fi
    done
    if [ "${#matches[@]}" -eq 1 ]; then
      echo "${matches[0]}"
      return
    fi
    # 4. Multiple specs — try title disambiguation against branch slug.
    if [ "${#matches[@]}" -gt 1 ] && [ -n "$slug" ]; then
      for spec_id in "${matches[@]}"; do
        if [ "$spec_id" = "$slug" ]; then
          echo "$spec_id"
          return
        fi
      done
    fi
  fi

  # 5. Fallback: slug + short-SHA, OR audit-<sha> when no usable slug.
  sha="$(git rev-parse --short=8 HEAD 2>/dev/null || echo "00000000")"
  if [ -n "$slug" ] && _audit_id_pattern_ok "${slug}-${sha}"; then
    echo "${slug}-${sha}"
    return
  fi
  echo "audit-${sha}"
}
