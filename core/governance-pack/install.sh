#!/usr/bin/env bash
# install.sh — interactive installer for governance-pack.
#
# Wires:
#   ~/.claude/hooks/governance-pack/{audit-gate,deny-prod-paths,no-coauthor-trailer,telemetry}.sh
#   ~/.claude/prod-paths.txt   (default denylist; SKIPPED if exists)
#   ~/.claude/settings.json    (MERGED — never overwritten; backed up first)
#   <repo>/.claude/settings.local.json  (only if invoked with --project)
#   <repo>/.claude/freeze.json          (only if invoked with --project)
#
# Behavior:
#   - Asks before merging into existing settings.json.
#   - Writes a timestamped backup before modification.
#   - Idempotent: safe to re-run; existing keys preserved.
#   - --dry-run: print plan, no changes.
#   - --project: also wire <repo>/.claude/settings.local.json + freeze.json.
#   - --force: skip confirmations (for CI / scripted installs).
#   - --postconditions-mode={shadow|blocking}: install postcondition-hook
#     in the given mode (default shadow). See feat:postcondition-hook
#     spec for the 30-day promote-to-blocking rationale (F2-7).
#
# Usage:
#   ./install.sh                              # global only, interactive
#   ./install.sh --project                    # global + project (run from repo root)
#   ./install.sh --dry-run                    # show what would change
#   ./install.sh --force                       # non-interactive
#   ./install.sh --refresh-prompts             # re-sync core/audit/prompts/* to install dest
#   ./install.sh --postconditions-mode=shadow  # install hook in shadow (default)
#
# Exit codes: 0 success · 1 user abort · 2 prerequisite missing · 3 merge failed.

set -euo pipefail

GP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="$GP_ROOT/hooks"
TEMPLATES_SRC="$GP_ROOT/templates"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
HOOKS_DST="$CLAUDE_HOME/hooks/governance-pack"
SETTINGS_DST="$CLAUDE_HOME/settings.json"
PROD_PATHS_DST="$CLAUDE_HOME/prod-paths.txt"

DRY_RUN=0
PROJECT_MODE=0
FORCE=0
REFRESH_PROMPTS=0
# feat:postcondition-hook — shadow-mode default per F2-7. Operator promotes
# to blocking via a one-line `jq` edit on ~/.claude/postconditions.json
# AFTER 30 days of FP-measurement; not via this flag. The flag exists so
# CI / Promptfoo cases can pre-flip the config in a controlled fixture.
POSTCONDITIONS_MODE="${POSTCONDITIONS_MODE:-shadow}"
# feat:quarantine-pack — Step 8 (advisory-mode hook). --quarantine-only runs
# Step 8 in isolation; --no-quarantine skips Step 8. Default: run.
QUARANTINE_ONLY=0
QUARANTINE_SKIP=0
ENABLE_SANDBOX=0
# v2.0 audit Finding-INFO: per-feature --no-<feature> flag parity. Each
# Step gates on its corresponding _SKIP variable; default 0 (=run).
RECOVERY_CLASS_SKIP=0
GIT_PUSH_GATE_SKIP=0
CRED_REFUSAL_SKIP=0
STALE_STAT_SKIP=0
LOOP_CB_SKIP=0
TYPED_TOOL_SURFACE_SKIP=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)         DRY_RUN=1 ;;
    --project)         PROJECT_MODE=1 ;;
    --force)           FORCE=1 ;;
    --refresh-prompts) REFRESH_PROMPTS=1 ;;
    --postconditions-mode=shadow)   POSTCONDITIONS_MODE=shadow ;;
    --postconditions-mode=blocking) POSTCONDITIONS_MODE=blocking ;;
    --postconditions-mode=*)
      echo "Unknown postconditions mode: ${arg#--postconditions-mode=} (expected shadow|blocking)" >&2
      exit 2 ;;
    --quarantine-only)        QUARANTINE_ONLY=1 ;;
    --no-quarantine)          QUARANTINE_SKIP=1 ;;
    --enable-sandbox)         ENABLE_SANDBOX=1 ;;
    --no-recovery-class)      RECOVERY_CLASS_SKIP=1 ;;
    --no-git-push-gate)       GIT_PUSH_GATE_SKIP=1 ;;
    --no-cred-refusal)        CRED_REFUSAL_SKIP=1 ;;
    --no-stale-stat)          STALE_STAT_SKIP=1 ;;
    --no-loop-cb)             LOOP_CB_SKIP=1 ;;
    --no-typed-tool-surface)  TYPED_TOOL_SURFACE_SKIP=1 ;;
    -h|--help)
      sed -n '2,34p' "$0"
      exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '[install] %s\n' "$*"; }

# do_or_dry: run argv directly (no shell re-interpretation). In dry-run mode
# print the planned argv and skip execution. Each call must be a single
# command — for compound operations, make two calls. Argv pass-through avoids
# shell-injection that the prior unsafe form (AUDIT-008) would have allowed
# if a future caller passed attacker-controlled material.
do_or_dry() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

confirm() {
  [ "$FORCE" -eq 1 ] && return 0
  local prompt="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] would prompt: %s [y/N] (auto-yes in dry-run)\n' "$prompt"
    return 0
  fi
  printf '%s [y/N] ' "$prompt"
  read -r reply
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# --- 0. Prerequisites ----------------------------------------------------
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: need either jq or python3 to merge settings.json." >&2
  exit 2
fi

if [ "$QUARANTINE_ONLY" -eq 1 ]; then
  log "skipping Steps 1-7 (--quarantine-only)"
else

# --- 1. Hooks dir + scripts ---------------------------------------------
log "Step 1: install hook scripts → $HOOKS_DST"
do_or_dry mkdir -p "$HOOKS_DST"
# Files prefixed with `_lib-` are sourced libraries, not standalone hooks —
# they declare functions and explicitly say "DO NOT execute directly". Skip
# the chmod +x for those so install perms match the source-tree convention
# (AUDIT-010). Use -p to preserve source permissions for libraries.
for src in "$HOOKS_SRC"/*.sh; do
  fname="$(basename "$src")"
  dst="$HOOKS_DST/$fname"
  is_lib=0
  case "$fname" in _lib-*) is_lib=1 ;; esac
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    if confirm "  $fname differs from installed version. Overwrite?"; then
      if [ "$is_lib" -eq 1 ]; then
        do_or_dry cp -p "$src" "$dst"
      else
        do_or_dry cp "$src" "$dst"
        do_or_dry chmod +x "$dst"
      fi
    else
      log "  skipped $fname"
    fi
  else
    if [ "$is_lib" -eq 1 ]; then
      do_or_dry cp -p "$src" "$dst"
    else
      do_or_dry cp "$src" "$dst"
      do_or_dry chmod +x "$dst"
    fi
  fi
done

# --- 2. prod-paths.txt --------------------------------------------------
log "Step 2: install default prod-paths denylist → $PROD_PATHS_DST"
if [ -f "$PROD_PATHS_DST" ]; then
  log "  exists; not overwriting (edit manually if needed)."
else
  do_or_dry cp "$TEMPLATES_SRC/prod-paths.txt" "$PROD_PATHS_DST"
fi

# --- 3. Merge global settings.json --------------------------------------
log "Step 3: merge global settings → $SETTINGS_DST"
NEW_SETTINGS="$TEMPLATES_SRC/global-settings.json"

merge_json() {
  local existing="$1" new="$2" out="$3"
  if command -v jq >/dev/null 2>&1; then
    jq -s '.[0] * .[1]' "$existing" "$new" > "$out"
  else
    python3 - "$existing" "$new" "$out" <<'PY'
import json,sys,collections
def deep_merge(a,b):
    if isinstance(a,dict) and isinstance(b,dict):
        out=dict(a)
        for k,v in b.items():
            out[k]=deep_merge(a.get(k),v) if k in a else v
        return out
    return b
with open(sys.argv[1]) as f: a=json.load(f)
with open(sys.argv[2]) as f: b=json.load(f)
with open(sys.argv[3],'w') as f: json.dump(deep_merge(a,b),f,indent=2)
PY
  fi
}

if [ -f "$SETTINGS_DST" ]; then
  if ! confirm "  $SETTINGS_DST exists. Merge governance-pack into it?"; then
    log "  user declined merge — global settings unchanged."
  else
    BAK="$SETTINGS_DST.bak.$(date +%Y%m%d-%H%M%S)"
    log "  backing up to $BAK"
    do_or_dry cp "$SETTINGS_DST" "$BAK"
    if [ "$DRY_RUN" -eq 0 ]; then
      TMP="$(mktemp)"
      if ! merge_json "$SETTINGS_DST" "$NEW_SETTINGS" "$TMP"; then
        echo "ERROR: merge failed; original at $BAK" >&2
        exit 3
      fi
      mv "$TMP" "$SETTINGS_DST"
      log "  merged → $SETTINGS_DST"
    fi
  fi
else
  do_or_dry mkdir -p "$CLAUDE_HOME"
  do_or_dry cp "$NEW_SETTINGS" "$SETTINGS_DST"
fi

# --- 4. Project-scoped (optional) ---------------------------------------
if [ "$PROJECT_MODE" -eq 1 ]; then
  PROJECT_DIR="$PWD"
  PROJECT_CLAUDE="$PROJECT_DIR/.claude"
  PROJECT_SETTINGS="$PROJECT_CLAUDE/settings.local.json"
  PROJECT_FREEZE="$PROJECT_CLAUDE/freeze.json"

  log "Step 4: project mode at $PROJECT_DIR"
  do_or_dry mkdir -p "$PROJECT_CLAUDE"

  if [ -f "$PROJECT_SETTINGS" ]; then
    if confirm "  $PROJECT_SETTINGS exists. Merge governance-pack project template into it?"; then
      BAK="$PROJECT_SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
      do_or_dry cp "$PROJECT_SETTINGS" "$BAK"
      if [ "$DRY_RUN" -eq 0 ]; then
        TMP="$(mktemp)"
        merge_json "$PROJECT_SETTINGS" "$TEMPLATES_SRC/project-settings.local.json" "$TMP"
        mv "$TMP" "$PROJECT_SETTINGS"
      fi
    fi
  else
    do_or_dry cp "$TEMPLATES_SRC/project-settings.local.json" "$PROJECT_SETTINGS"
  fi

  if [ -f "$PROJECT_FREEZE" ]; then
    log "  $PROJECT_FREEZE exists; not overwriting."
  else
    do_or_dry cp "$TEMPLATES_SRC/freeze.json" "$PROJECT_FREEZE"
  fi
fi

# --- 5. Compose-with-core-config check ----------------------------------
# core-config v1.4.2+ ships these hooks unconditionally; pure-governance-pack
# install (no core-config) still warns, since governance-pack composes ON TOP.
log "Step 5: compose-with-core-config check"
for required in block-destructive.sh pre-edit-stash.sh; do
  if [ ! -f "$CLAUDE_HOME/hooks/$required" ]; then
    log "  WARN: $CLAUDE_HOME/hooks/$required not found — install core-config (P0-01) first"
    log "        Run: ${GP_ROOT}/../core-config/install.sh"
    log "        Otherwise the global-settings.json template will fail with exit 127."
  fi
done

# --- 6. Project commit-msg hook (Phase 8 audit gate, optional) ----------
# When invoked with --project, install commit-msg-audit-check.sh into
# <repo>/.git/hooks/commit-msg. Idempotent: re-running the installer detects
# an existing reference and skips. If a different commit-msg script already
# exists, we ask before appending so user's prior logic is preserved.
#
# Why commit-msg (not pre-commit): commit-msg receives the path to the
# message file as $1, which holds the message being authored RIGHT NOW.
# pre-commit only sees `.git/COMMIT_EDITMSG` from the PREVIOUS commit (or
# empty for first commit) — that bug was AUDIT-001 in audit-builtin.
#
# Why $HOOKS_DST (not $HOOKS_SRC): the wrapper installed into .git/hooks
# must point to the stable install location (~/.claude/hooks/governance-pack/).
# Pointing at the source clone breaks silently if the user moves/deletes
# their checkout — that bug was AUDIT-005 in audit-builtin.
if [ "$PROJECT_MODE" -eq 1 ]; then
  PROJECT_GIT_HOOKS="$PROJECT_DIR/.git/hooks"
  COMMIT_MSG_DST="$PROJECT_GIT_HOOKS/commit-msg"
  COMMIT_MSG_SRC="$HOOKS_DST/commit-msg-audit-check.sh"

  log "Step 6: install commit-msg-audit-check → $COMMIT_MSG_DST"
  if [ ! -d "$PROJECT_GIT_HOOKS" ]; then
    log "  WARN: $PROJECT_GIT_HOOKS does not exist (not a git repo or .git removed) — skipping"
  elif [ ! -f "$COMMIT_MSG_SRC" ] && [ "$DRY_RUN" -eq 0 ]; then
    log "  WARN: $COMMIT_MSG_SRC missing — Step 1 must have run first; skipping"
  else
    if [ -f "$COMMIT_MSG_DST" ]; then
      if grep -q "commit-msg-audit-check" "$COMMIT_MSG_DST" 2>/dev/null; then
        log "  $COMMIT_MSG_DST already references commit-msg-audit-check; idempotent skip"
      else
        if confirm "  $COMMIT_MSG_DST exists with other content. Append governance-pack audit check?"; then
          BAK="$COMMIT_MSG_DST.bak.$(date +%Y%m%d-%H%M%S)"
          log "  backing up existing commit-msg to $BAK"
          do_or_dry cp "$COMMIT_MSG_DST" "$BAK"
          if [ "$DRY_RUN" -eq 1 ]; then
            printf '[dry-run] append: bash %q "$@" to %s\n' "$COMMIT_MSG_SRC" "$COMMIT_MSG_DST"
          else
            {
              printf '\n# governance-pack audit gate (added %s)\n' "$(date +%Y-%m-%d)"
              printf 'bash %q "$@" || exit $?\n' "$COMMIT_MSG_SRC"
            } >> "$COMMIT_MSG_DST"
            chmod +x "$COMMIT_MSG_DST"
          fi
        else
          log "  user declined append — commit-msg unchanged"
        fi
      fi
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] write: %s -> bash %q "$@"\n' "$COMMIT_MSG_DST" "$COMMIT_MSG_SRC"
      else
        {
          printf '#!/usr/bin/env bash\n'
          printf '# governance-pack audit gate (installed %s)\n' "$(date +%Y-%m-%d)"
          printf 'bash %q "$@"\n' "$COMMIT_MSG_SRC"
        } > "$COMMIT_MSG_DST"
        chmod +x "$COMMIT_MSG_DST"
      fi
    fi
  fi

  log "  Tip: copy .github/workflows/audit-required.yml from claude-skills"
  log "       into <your-repo>/.github/workflows/ to enable the CI merge gate."
fi

# --- 7. Refresh audit prompts (optional) --------------------------------
# When --refresh-prompts is set, re-sync core/audit/prompts/*.md into the
# install destination idempotently. The flag is forward-compatible: any
# *.md file added under core/audit/prompts/ in future versions is picked up
# automatically. Idempotent: clobber-on-copy. Prompts are canonical and
# base-SHA-bound at audit time on the CI gate, so the destination is
# operator ergonomics — not the audit's integrity surface.
if [ "$REFRESH_PROMPTS" -eq 1 ]; then
  log "Step 7: refresh audit prompts → \$CLAUDE_HOME/skills/audit/prompts"
  AUDIT_PROMPTS_SRC="$(cd "$GP_ROOT/.." && pwd)/audit/prompts"
  AUDIT_PROMPTS_DST="$CLAUDE_HOME/skills/audit/prompts"
  if [ ! -d "$AUDIT_PROMPTS_SRC" ]; then
    log "  WARN: $AUDIT_PROMPTS_SRC not found — skipping (run from claude-skills checkout)"
  else
    do_or_dry mkdir -p "$AUDIT_PROMPTS_DST"
    for src in "$AUDIT_PROMPTS_SRC"/*.md; do
      [ -e "$src" ] || continue
      do_or_dry cp "$src" "$AUDIT_PROMPTS_DST/$(basename "$src")"
    done
  fi
fi

# --- 8. Postcondition hook (feat:postcondition-hook) -------------------
# Charter §2.1 enforcement upgrade. F2-1 flat command-pattern table at
# ~/.claude/postconditions.d/. F2-7 shadow-mode default. The hook script
# itself was copied in Step 1 (it lives alongside the other governance
# hooks); this step seeds the operator-owned table + config and registers
# the hook's PostToolUse matcher in ~/.claude/settings.json.
log "Step 8: install postcondition-hook (mode=$POSTCONDITIONS_MODE)"

POSTCONDITIONS_DIR="$CLAUDE_HOME/postconditions.d"
POSTCONDITIONS_CONF="$CLAUDE_HOME/postconditions.json"
POSTCONDITIONS_TEMPLATES_SRC="$TEMPLATES_SRC/postconditions.d"

# 8a. Seed ~/.claude/postconditions.d/ from templates. Preserve operator
# edits by default — only copy files whose target does NOT exist (override
# with POSTCONDITIONS_FORCE=1 to clobber).
do_or_dry mkdir -p "$POSTCONDITIONS_DIR"
if [ -d "$POSTCONDITIONS_TEMPLATES_SRC" ]; then
  for src in "$POSTCONDITIONS_TEMPLATES_SRC"/*.sh; do
    [ -e "$src" ] || continue
    dst="$POSTCONDITIONS_DIR/$(basename "$src")"
    if [ -f "$dst" ] && [ "${POSTCONDITIONS_FORCE:-0}" != "1" ]; then
      log "  preserve $(basename "$dst") (operator edits kept; POSTCONDITIONS_FORCE=1 to overwrite)"
    else
      do_or_dry cp "$src" "$dst"
      do_or_dry chmod +x "$dst"
    fi
  done
else
  log "  WARN: $POSTCONDITIONS_TEMPLATES_SRC missing — postcondition templates not seeded"
fi

# 8b. Seed ~/.claude/postconditions.json. Only copy if absent. If the
# operator passed --postconditions-mode=blocking, mutate `.mode` AFTER
# copy so the absent-file branch + the present-file branch agree.
if [ -f "$POSTCONDITIONS_CONF" ]; then
  log "  $POSTCONDITIONS_CONF exists; preserving (edit '.mode' manually to flip shadow→blocking)"
else
  if [ -f "$TEMPLATES_SRC/postconditions.json" ]; then
    do_or_dry cp "$TEMPLATES_SRC/postconditions.json" "$POSTCONDITIONS_CONF"
    if [ "$POSTCONDITIONS_MODE" = "blocking" ] && [ "$DRY_RUN" -eq 0 ]; then
      if command -v jq >/dev/null 2>&1; then
        TMP="$(mktemp)"
        jq '.mode = "blocking"' "$POSTCONDITIONS_CONF" > "$TMP" && mv "$TMP" "$POSTCONDITIONS_CONF"
        log "  set mode=blocking in $POSTCONDITIONS_CONF"
      else
        log "  WARN: jq missing — left $POSTCONDITIONS_CONF with default mode=shadow; edit manually"
      fi
    fi
  else
    log "  WARN: $TEMPLATES_SRC/postconditions.json missing — config not seeded"
  fi
fi

# 8c. Register the hook in ~/.claude/settings.json under PostToolUse with
# matcher Bash|Edit|Write|MultiEdit|NotebookEdit. Idempotent: skip if
# `postcondition-hook` already appears in the file.
HOOK_INSTALLED_PATH="$HOOKS_DST/postcondition-hook.sh"
if [ -f "$SETTINGS_DST" ] && grep -q 'postcondition-hook' "$SETTINGS_DST" 2>/dev/null; then
  log "  $SETTINGS_DST already registers postcondition-hook (idempotent skip)"
elif [ -f "$SETTINGS_DST" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] register PostToolUse hook in %s -> %s (matcher: Bash|Edit|Write|MultiEdit|NotebookEdit)\n' \
      "$SETTINGS_DST" "$HOOK_INSTALLED_PATH"
  else
    BAK="$SETTINGS_DST.bak.postcondition.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_DST" "$BAK"
    if command -v jq >/dev/null 2>&1; then
      TMP="$(mktemp)"
      jq --arg cmd "$HOOK_INSTALLED_PATH" '
        .hooks //= {}
        | .hooks.PostToolUse //= []
        | .hooks.PostToolUse += [{
            "matcher": "Bash|Edit|Write|MultiEdit|NotebookEdit",
            "hooks": [{"type": "command", "command": $cmd, "timeout": 8000}]
          }]
      ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"
      log "  registered postcondition-hook in $SETTINGS_DST (backup: $BAK)"
    else
      log "  WARN: jq missing — cannot append PostToolUse entry to $SETTINGS_DST"
      log "        Add manually: hooks.PostToolUse += matcher='Bash|Edit|Write|MultiEdit|NotebookEdit'"
      log "                      command=$HOOK_INSTALLED_PATH"
    fi
  fi
else
  log "  $SETTINGS_DST missing — skipped registration (Step 3 should have created it)"
fi

log "  Authoring postcondition snippets: see core/governance-pack/README.md §'Phase 2.1 enforcement'"
log "  F2-6 stealth-cost notice: state-changing skills declare ~10 lines of verification per pattern."

fi  # end QUARANTINE_ONLY guard around Steps 1-8

# --- 9. Quarantine-pack (feat:quarantine-pack — charter §2.2 sub-clause #2) -
# v2.0 P0 Top-5 #2. PostToolUse hook on matcher mcp__.*|WebFetch|Read.
# Advisory-only mode per F2-2 contract reality: hook emits a
# [QUARANTINE-NOTICE: ...] payload via hookSpecificOutput.additionalContext
# so the next-turn context carries the boundary tag. Always exits 0.
#
# Honors --no-quarantine (skip) and --quarantine-only (run only this step).
if [ "$QUARANTINE_SKIP" -eq 1 ]; then
  log "Step 9: quarantine-pack skipped (--no-quarantine)"
else
  log "Step 9: install quarantine-pack (advisory mode)"

  QP_HOOKS_SRC="$(cd "$GP_ROOT/.." && pwd)/quarantine-pack/hooks"
  QP_TEMPLATES_SRC="$(cd "$GP_ROOT/.." && pwd)/quarantine-pack/templates"
  QP_HOOKS_DST="$CLAUDE_HOME/hooks/quarantine-pack"
  QP_DIR_DST="$CLAUDE_HOME/quarantine.d"
  QP_CONF_DST="$CLAUDE_HOME/quarantine.json"
  QP_ALLOWLIST_DST="$QP_DIR_DST/trusted-mcp-allowlist.txt"

  if [ ! -d "$QP_HOOKS_SRC" ] || [ ! -d "$QP_TEMPLATES_SRC" ]; then
    log "  WARN: quarantine-pack source missing under $(cd "$GP_ROOT/.." && pwd)/quarantine-pack — skipping (run from claude-skills checkout)"
  else
    # 9a. Hooks dir (~/.claude/hooks/quarantine-pack/).
    do_or_dry mkdir -p "$QP_HOOKS_DST"
    for src in "$QP_HOOKS_SRC"/*.sh; do
      [ -e "$src" ] || continue
      fname="$(basename "$src")"
      dst="$QP_HOOKS_DST/$fname"
      case "$fname" in
        _lib-*)
          do_or_dry cp -p "$src" "$dst"
          ;;
        *)
          do_or_dry cp "$src" "$dst"
          do_or_dry chmod +x "$dst"
          ;;
      esac
    done
    # Advisory-text template lives alongside the hook (not in quarantine.d/).
    do_or_dry cp "$QP_TEMPLATES_SRC/quarantine-notice.template" "$QP_HOOKS_DST/quarantine-notice.template"

    # 9b. Trusted-MCP allowlist (~/.claude/quarantine.d/). Preserve operator
    # edits unless POSTCONDITIONS_FORCE=1 (re-uses the existing flag pattern).
    do_or_dry mkdir -p "$QP_DIR_DST"
    if [ -f "$QP_ALLOWLIST_DST" ] && [ "${POSTCONDITIONS_FORCE:-0}" != "1" ]; then
      log "  preserve $QP_ALLOWLIST_DST (operator edits kept; POSTCONDITIONS_FORCE=1 to overwrite)"
    else
      do_or_dry cp "$QP_TEMPLATES_SRC/trusted-mcp-allowlist.txt" "$QP_ALLOWLIST_DST"
    fi

    # 9c. Mode config (~/.claude/quarantine.json). Only copy if absent.
    if [ -f "$QP_CONF_DST" ]; then
      log "  $QP_CONF_DST exists; preserving"
    else
      do_or_dry cp "$QP_TEMPLATES_SRC/quarantine.json" "$QP_CONF_DST"
    fi

    # 9d. Register PostToolUse matcher in ~/.claude/settings.json.
    # Idempotent: skip if `wrap-mcp-output` already appears in the file.
    QP_HOOK_INSTALLED_PATH="$QP_HOOKS_DST/wrap-mcp-output.sh"
    if [ -f "$SETTINGS_DST" ] && grep -q 'wrap-mcp-output' "$SETTINGS_DST" 2>/dev/null; then
      log "  $SETTINGS_DST already registers wrap-mcp-output (idempotent skip)"
    elif [ -f "$SETTINGS_DST" ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] register PostToolUse hook in %s -> %s (matcher: mcp__.*|WebFetch|Read, timeout 5000)\n' \
          "$SETTINGS_DST" "$QP_HOOK_INSTALLED_PATH"
      else
        BAK="$SETTINGS_DST.bak.quarantine.$(date +%Y%m%d-%H%M%S)"
        cp "$SETTINGS_DST" "$BAK"
        if command -v jq >/dev/null 2>&1; then
          TMP="$(mktemp)"
          jq --arg cmd "$QP_HOOK_INSTALLED_PATH" '
            .hooks //= {}
            | .hooks.PostToolUse //= []
            | .hooks.PostToolUse += [{
                "matcher": "mcp__.*|WebFetch|Read",
                "hooks": [{"type": "command", "command": $cmd, "timeout": 5000}]
              }]
          ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"
          log "  registered wrap-mcp-output in $SETTINGS_DST (backup: $BAK)"
        else
          log "  WARN: jq missing — cannot append PostToolUse entry to $SETTINGS_DST"
          log "        Add manually: hooks.PostToolUse += matcher='mcp__.*|WebFetch|Read'"
          log "                      command=$QP_HOOK_INSTALLED_PATH timeout=5000"
        fi
      fi
    else
      log "  $SETTINGS_DST missing — skipped registration (Step 3 should have created it)"
    fi

    log "  [install] quarantine-pack hook registered (advisory mode); see core/quarantine-pack/README.md"
  fi
fi

# --- 10. recovery-class-fragment (feat:recovery-class-fragment, OPT-IN) -
# v2.0 P1 #4. PostToolUse hook on matcher Bash|Edit|Write that matches
# tool_response.stderr against templates/recovery-classes.tsv and emits a
# [RECOVERY-HINT: class=<class> action=<primitive>] advisory when exactly
# ONE class matches. Skill is auto_trigger:false — operators opt in by
# editing ~/.claude/settings.json themselves (see SKILL.md §Install).
# This step copies the hook + TSV to ~/.claude/hooks/recovery-class-fragment/
# but does NOT register a matcher in settings.json — opt-in stays opt-in.
if [ "$RECOVERY_CLASS_SKIP" -eq 1 ]; then
  log "Step 10: recovery-class-fragment skipped (--no-recovery-class)"
else
log "Step 10: stage recovery-class-fragment (opt-in; no settings.json edit)"
RC_HOOKS_SRC="$(cd "$GP_ROOT/.." && pwd)/recovery-class-fragment/hooks"
RC_TPL_SRC="$(cd "$GP_ROOT/.." && pwd)/recovery-class-fragment/templates"
RC_HOOKS_DST="$CLAUDE_HOME/hooks/recovery-class-fragment"
if [ ! -d "$RC_HOOKS_SRC" ]; then
  log "  WARN: recovery-class-fragment source missing under $(cd "$GP_ROOT/.." && pwd)/recovery-class-fragment — skipping"
else
  do_or_dry mkdir -p "$RC_HOOKS_DST"
  for src in "$RC_HOOKS_SRC"/*.sh; do
    [ -e "$src" ] || continue
    do_or_dry cp "$src" "$RC_HOOKS_DST/$(basename "$src")"
    do_or_dry chmod +x "$RC_HOOKS_DST/$(basename "$src")"
  done
  if [ -f "$RC_TPL_SRC/recovery-classes.tsv" ]; then
    do_or_dry cp "$RC_TPL_SRC/recovery-classes.tsv" "$RC_HOOKS_DST/recovery-classes.tsv"
  fi
  log "  staged recovery-class-fragment hook + TSV at $RC_HOOKS_DST"
  log "  Operator opt-in: append a PostToolUse matcher Bash|Edit|Write -> $RC_HOOKS_DST/recovery-classify.sh"
  log "  See core/recovery-class-fragment/README.md §Install for the jq one-liner."
fi

fi  # end --no-recovery-class gate (Step 10)

# --- 11. git-force-push-gate (feat:git-force-push-gate, P1 #1) ----------
# PreToolUse(Bash) hook refusing `git push --force` / `--force-with-lease` and
# `--no-verify` on protected branches. Hard-block exit 2.
if [ "$GIT_PUSH_GATE_SKIP" -eq 1 ]; then
  log "Step 11: git-force-push-gate skipped (--no-git-push-gate)"
else
log "Step 11: install git-force-push-gate"
GFP_HOOKS_SRC="$(cd "$GP_ROOT/.." && pwd)/git-force-push-gate/hooks"
GFP_TPL_SRC="$(cd "$GP_ROOT/.." && pwd)/git-force-push-gate/templates"
GFP_HOOKS_DST="$CLAUDE_HOME/hooks/git-force-push-gate"
GFP_DIR_DST="$CLAUDE_HOME/git-force-push-gate"
GFP_ALLOW_DST="$CLAUDE_HOME/git-force-push-gate-allow"
GFP_PROTECTED_DST="$GFP_DIR_DST/protected-branches.txt"

if [ ! -d "$GFP_HOOKS_SRC" ]; then
  log "  WARN: git-force-push-gate source missing — skipping"
else
  do_or_dry mkdir -p "$GFP_HOOKS_DST" "$GFP_DIR_DST" "$GFP_ALLOW_DST"
  for src in "$GFP_HOOKS_SRC"/*.sh; do
    [ -e "$src" ] || continue
    do_or_dry cp "$src" "$GFP_HOOKS_DST/$(basename "$src")"
    do_or_dry chmod +x "$GFP_HOOKS_DST/$(basename "$src")"
  done
  if [ -f "$GFP_PROTECTED_DST" ] && [ "${POSTCONDITIONS_FORCE:-0}" != "1" ]; then
    log "  preserve $GFP_PROTECTED_DST (operator edits kept)"
  else
    do_or_dry cp "$GFP_TPL_SRC/protected-branches.txt" "$GFP_PROTECTED_DST"
  fi
  GFP_HOOK_INSTALLED="$GFP_HOOKS_DST/git-push-gate.sh"
  if [ -f "$SETTINGS_DST" ] && grep -q 'git-push-gate' "$SETTINGS_DST" 2>/dev/null; then
    log "  $SETTINGS_DST already registers git-push-gate (idempotent skip)"
  elif [ -f "$SETTINGS_DST" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[dry-run] register PreToolUse(Bash) -> %s\n' "$GFP_HOOK_INSTALLED"
    elif command -v jq >/dev/null 2>&1; then
      BAK="$SETTINGS_DST.bak.gfp.$(date +%Y%m%d-%H%M%S)"
      cp "$SETTINGS_DST" "$BAK"
      TMP="$(mktemp)"
      jq --arg cmd "$GFP_HOOK_INSTALLED" '
        .hooks //= {} | .hooks.PreToolUse //= []
        | .hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":$cmd,"timeout":5000}]}]
      ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"
      log "  registered git-push-gate (backup: $BAK)"
    fi
  fi
fi

fi  # end --no-git-push-gate gate (Step 11)

# --- 12. hardcoded-credential-refusal (P1 #2) ---------------------------
if [ "$CRED_REFUSAL_SKIP" -eq 1 ]; then
  log "Step 12: hardcoded-credential-refusal skipped (--no-cred-refusal)"
else
log "Step 12: install hardcoded-credential-refusal"
HCR_HOOKS_SRC="$(cd "$GP_ROOT/.." && pwd)/hardcoded-credential-refusal/hooks"
HCR_TPL_SRC="$(cd "$GP_ROOT/.." && pwd)/hardcoded-credential-refusal/templates"
HCR_HOOKS_DST="$CLAUDE_HOME/hooks/hardcoded-credential-refusal"
HCR_DIR_DST="$CLAUDE_HOME/hardcoded-credential-refusal"
HCR_BANK_DST="$HCR_DIR_DST/credential-regex-bank.txt"

if [ ! -d "$HCR_HOOKS_SRC" ]; then
  log "  WARN: hardcoded-credential-refusal source missing — skipping"
else
  do_or_dry mkdir -p "$HCR_HOOKS_DST" "$HCR_DIR_DST"
  for src in "$HCR_HOOKS_SRC"/*.sh; do
    [ -e "$src" ] || continue
    do_or_dry cp "$src" "$HCR_HOOKS_DST/$(basename "$src")"
    do_or_dry chmod +x "$HCR_HOOKS_DST/$(basename "$src")"
  done
  if [ -f "$HCR_BANK_DST" ] && [ "${POSTCONDITIONS_FORCE:-0}" != "1" ]; then
    log "  preserve $HCR_BANK_DST (operator edits kept)"
  else
    do_or_dry cp "$HCR_TPL_SRC/credential-regex-bank.txt" "$HCR_BANK_DST"
  fi
  HCR_HOOK_INSTALLED="$HCR_HOOKS_DST/credential-scan.sh"
  if [ -f "$SETTINGS_DST" ] && grep -q 'credential-scan' "$SETTINGS_DST" 2>/dev/null; then
    log "  $SETTINGS_DST already registers credential-scan (idempotent skip)"
  elif [ -f "$SETTINGS_DST" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[dry-run] register PreToolUse(Edit|Write|MultiEdit) -> %s\n' "$HCR_HOOK_INSTALLED"
    elif command -v jq >/dev/null 2>&1; then
      BAK="$SETTINGS_DST.bak.hcr.$(date +%Y%m%d-%H%M%S)"
      cp "$SETTINGS_DST" "$BAK"
      TMP="$(mktemp)"
      jq --arg cmd "$HCR_HOOK_INSTALLED" '
        .hooks //= {} | .hooks.PreToolUse //= []
        | .hooks.PreToolUse += [{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":$cmd,"timeout":5000}]}]
      ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"
      log "  registered credential-scan (backup: $BAK)"
    fi
  fi
fi

fi  # end --no-cred-refusal gate (Step 12)

# --- 13. file-write-stale-stat-refusal (P1 #3) --------------------------
if [ "$STALE_STAT_SKIP" -eq 1 ]; then
  log "Step 13: file-write-stale-stat-refusal skipped (--no-stale-stat)"
else
log "Step 13: install file-write-stale-stat-refusal"
FWS_HOOKS_SRC="$(cd "$GP_ROOT/.." && pwd)/file-write-stale-stat-refusal/hooks"
FWS_HOOKS_DST="$CLAUDE_HOME/hooks/file-write-stale-stat-refusal"

if [ ! -d "$FWS_HOOKS_SRC" ]; then
  log "  WARN: file-write-stale-stat-refusal source missing — skipping"
else
  do_or_dry mkdir -p "$FWS_HOOKS_DST"
  for src in "$FWS_HOOKS_SRC"/*.sh; do
    [ -e "$src" ] || continue
    do_or_dry cp "$src" "$FWS_HOOKS_DST/$(basename "$src")"
    do_or_dry chmod +x "$FWS_HOOKS_DST/$(basename "$src")"
  done
  FWS_CACHE_HOOK="$FWS_HOOKS_DST/cache-mtime-on-read.sh"
  FWS_CHECK_HOOK="$FWS_HOOKS_DST/file-stat-check.sh"
  # v1.7.1 root-cause fix for v1.7.0 install bug: previously this block
  # checked only "is file-stat-check registered?" and skipped wholesale,
  # which silently dropped any matcher widening on upgrade (e.g. v1.7.0
  # widened cache-mtime PostToolUse matcher from "Read" to
  # "Read|Edit|Write|MultiEdit" but installs over a v1.6.0-shaped settings
  # never picked it up). Now: ensure BOTH entries exist AND have canonical
  # matchers; add missing entries; rewrite stale matchers in place.
  FWS_CACHE_MATCHER='Read|Edit|Write|MultiEdit'
  FWS_CHECK_MATCHER='Edit|Write|MultiEdit'
  if [ -f "$SETTINGS_DST" ] && command -v jq >/dev/null 2>&1; then
    # Detect canonical state via jq (matcher-aware, not grep-aware).
    CACHE_PRESENT="$(jq --arg c "$FWS_CACHE_HOOK" --arg m "$FWS_CACHE_MATCHER" \
      '[.hooks.PostToolUse[]? | select(.hooks[]?.command == $c) | select(.matcher == $m)] | length' \
      "$SETTINGS_DST" 2>/dev/null || echo 0)"
    CHECK_PRESENT="$(jq --arg c "$FWS_CHECK_HOOK" --arg m "$FWS_CHECK_MATCHER" \
      '[.hooks.PreToolUse[]? | select(.hooks[]?.command == $c) | select(.matcher == $m)] | length' \
      "$SETTINGS_DST" 2>/dev/null || echo 0)"
    if [ "${CACHE_PRESENT:-0}" -ge 1 ] && [ "${CHECK_PRESENT:-0}" -ge 1 ]; then
      log "  $SETTINGS_DST already registers file-stat-check + cache-mtime with canonical matchers (idempotent skip)"
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] register/canonicalize file-write-stale-stat-refusal hooks\n'
      else
        BAK="$SETTINGS_DST.bak.fws.$(date +%Y%m%d-%H%M%S)"
        cp "$SETTINGS_DST" "$BAK"
        TMP="$(mktemp)"
        # Canonicalize: drop any prior entry referencing these two hooks
        # (regardless of matcher), then add fresh canonical entries. This
        # is matcher-rewrite, not duplicate-add.
        jq --arg cache "$FWS_CACHE_HOOK" --arg check "$FWS_CHECK_HOOK" \
           --arg cmat "$FWS_CACHE_MATCHER" --arg pmat "$FWS_CHECK_MATCHER" '
          .hooks //= {}
          | .hooks.PostToolUse //= []
          | .hooks.PreToolUse  //= []
          | .hooks.PostToolUse |= map(select((.hooks // []) | map(.command) | index($cache) | not))
          | .hooks.PreToolUse  |= map(select((.hooks // []) | map(.command) | index($check) | not))
          | .hooks.PostToolUse += [{"matcher":$cmat,"hooks":[{"type":"command","command":$cache,"timeout":5000}]}]
          | .hooks.PreToolUse  += [{"matcher":$pmat,"hooks":[{"type":"command","command":$check,"timeout":5000}]}]
        ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"
        log "  registered/canonicalized file-write-stale-stat-refusal (backup: $BAK)"
      fi
    fi
  elif [ -f "$SETTINGS_DST" ]; then
    log "  WARN: jq missing — cannot canonicalize file-stat matchers; install with jq present to enable"
  fi
fi

fi  # end --no-stale-stat gate (Step 13)

# --- 14. eval-contamination-probe (P1 #5, charter §7 SLO line) ---------
# This skill is documentation + templates + a self-test. No runtime hook;
# nothing to register in settings.json. Step 14 logs the cross-link only.
log "Step 14: eval-contamination-probe is template-only (no settings.json edit)"
log "  See core/eval-contamination-probe/README.md and §7 SLO list in charter-v1.1.md"
log "  Run the self-test: bash core/eval-contamination-probe/tests/test-probe-detect.sh"

# --- 15. loop-circuit-breaker (Top-5 #3, charter §2.2 sub-clause #1) ----
if [ "$LOOP_CB_SKIP" -eq 1 ]; then
  log "Step 15: loop-circuit-breaker skipped (--no-loop-cb)"
else
log "Step 15: install loop-circuit-breaker"
LCB_HOOKS_SRC="$(cd "$GP_ROOT/.." && pwd)/loop-circuit-breaker/hooks"
LCB_TPL_SRC="$(cd "$GP_ROOT/.." && pwd)/loop-circuit-breaker/templates"
LCB_HOOKS_DST="$CLAUDE_HOME/hooks/loop-circuit-breaker"
LCB_DIR_DST="$CLAUDE_HOME/loop-circuit-breaker"

if [ ! -d "$LCB_HOOKS_SRC" ]; then
  log "  WARN: loop-circuit-breaker source missing — skipping"
else
  do_or_dry mkdir -p "$LCB_HOOKS_DST" "$LCB_DIR_DST"
  for src in "$LCB_HOOKS_SRC"/*.sh; do
    [ -e "$src" ] || continue
    do_or_dry cp "$src" "$LCB_HOOKS_DST/$(basename "$src")"
    do_or_dry chmod +x "$LCB_HOOKS_DST/$(basename "$src")"
  done
  for src in "$LCB_TPL_SRC"/*; do
    [ -e "$src" ] || continue
    do_or_dry cp "$src" "$LCB_HOOKS_DST/$(basename "$src")"
  done
  LCB_PRE="$LCB_HOOKS_DST/pretooluse-count-hash.sh"
  LCB_POST="$LCB_HOOKS_DST/posttooluse-cost.sh"
  LCB_STOP="$LCB_HOOKS_DST/stop-summary.sh"
  if [ -f "$SETTINGS_DST" ] && grep -q 'pretooluse-count-hash' "$SETTINGS_DST" 2>/dev/null; then
    log "  $SETTINGS_DST already registers loop-circuit-breaker (idempotent skip)"
  elif [ -f "$SETTINGS_DST" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[dry-run] register loop-circuit-breaker hooks\n'
    elif command -v jq >/dev/null 2>&1; then
      BAK="$SETTINGS_DST.bak.lcb.$(date +%Y%m%d-%H%M%S)"
      cp "$SETTINGS_DST" "$BAK"
      TMP="$(mktemp)"
      jq --arg pre "$LCB_PRE" --arg post "$LCB_POST" --arg stop "$LCB_STOP" '
        .hooks //= {}
        | .hooks.PreToolUse //= []
        | .hooks.PostToolUse //= []
        | .hooks.Stop //= []
        | .hooks.PreToolUse  += [{"matcher":".*","hooks":[{"type":"command","command":$pre,"timeout":5000}]}]
        | .hooks.PostToolUse += [{"matcher":".*","hooks":[{"type":"command","command":$post,"timeout":5000}]}]
        | .hooks.Stop        += [{"matcher":".*","hooks":[{"type":"command","command":$stop,"timeout":5000}]}]
      ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"
      log "  registered loop-circuit-breaker (backup: $BAK)"
    fi
  fi
fi

fi  # end --no-loop-cb gate (Step 15)

# --- 16. typed-tool-surface (Top-5 #4, charter §2.2 mechanism) -----------
if [ "$TYPED_TOOL_SURFACE_SKIP" -eq 1 ]; then
  log "Step 16: typed-tool-surface skipped (--no-typed-tool-surface)"
else
log "Step 16: install typed-tool-surface"
TTS_HOOKS_SRC="$(cd "$GP_ROOT/.." && pwd)/typed-tool-surface/hooks"
TTS_HOOKS_DST="$CLAUDE_HOME/hooks/typed-tool-surface"
TTS_CONF_DST="$CLAUDE_HOME/typed-tool-surface.json"

if [ ! -d "$TTS_HOOKS_SRC" ]; then
  log "  WARN: typed-tool-surface source missing — skipping"
else
  do_or_dry mkdir -p "$TTS_HOOKS_DST"
  for src in "$TTS_HOOKS_SRC"/*.sh; do
    [ -e "$src" ] || continue
    do_or_dry cp "$src" "$TTS_HOOKS_DST/$(basename "$src")"
    do_or_dry chmod +x "$TTS_HOOKS_DST/$(basename "$src")"
  done
  if [ ! -f "$TTS_CONF_DST" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[dry-run] write %s mode=advisory\n' "$TTS_CONF_DST"
    else
      printf '{"mode":"advisory"}\n' > "$TTS_CONF_DST"
    fi
  fi
  TTS_HOOK_INSTALLED="$TTS_HOOKS_DST/schema-validate.sh"
  if [ -f "$SETTINGS_DST" ] && grep -q 'schema-validate' "$SETTINGS_DST" 2>/dev/null; then
    log "  $SETTINGS_DST already registers schema-validate (idempotent skip)"
  elif [ -f "$SETTINGS_DST" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[dry-run] register PreToolUse(*) -> %s\n' "$TTS_HOOK_INSTALLED"
    elif command -v jq >/dev/null 2>&1; then
      BAK="$SETTINGS_DST.bak.tts.$(date +%Y%m%d-%H%M%S)"
      cp "$SETTINGS_DST" "$BAK"
      TMP="$(mktemp)"
      jq --arg cmd "$TTS_HOOK_INSTALLED" '
        .hooks //= {} | .hooks.PreToolUse //= []
        | .hooks.PreToolUse += [{"matcher":".*","hooks":[{"type":"command","command":$cmd,"timeout":5000}]}]
      ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"
      log "  registered typed-tool-surface (backup: $BAK)"
    fi
  fi
fi

fi  # end --no-typed-tool-surface gate (Step 16)

# --- 17. sandbox-default-on (Top-5 #5, charter §2.2 example + §2.4-bis) -
log "Step 17: stage sandbox-default-on (flag --enable-sandbox: $ENABLE_SANDBOX)"
SBX_FLAG_SRC="$(cd "$GP_ROOT/.." && pwd)/sandbox-default-on/install-flag.sh"
SBX_TPL_SRC="$(cd "$GP_ROOT/.." && pwd)/sandbox-default-on/templates"
SBX_DIR_DST="$CLAUDE_HOME/sandbox-default-on"

if [ ! -f "$SBX_FLAG_SRC" ]; then
  log "  WARN: sandbox-default-on source missing — skipping"
else
  do_or_dry mkdir -p "$SBX_DIR_DST"
  do_or_dry cp "$SBX_FLAG_SRC" "$SBX_DIR_DST/install-flag.sh"
  do_or_dry chmod +x "$SBX_DIR_DST/install-flag.sh"
  if [ -d "$SBX_TPL_SRC" ]; then
    for f in "$SBX_TPL_SRC"/*.md; do
      [ -e "$f" ] || continue
      do_or_dry cp "$f" "$SBX_DIR_DST/$(basename "$f")"
    done
  fi
  if [ "$ENABLE_SANDBOX" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "  [dry-run] would invoke $SBX_DIR_DST/install-flag.sh to set defaultMode=sandbox"
    else
      bash "$SBX_DIR_DST/install-flag.sh" || log "  WARN: sandbox-default-on flag returned non-zero"
    fi
  else
    log "  --enable-sandbox NOT set; staged only. Re-run with --enable-sandbox to flip."
  fi
fi

# --- 18. multi-agent-merge-discipline (v1.8.0; install § shipped in v1.9.1) -
# Install the per-project hook globally at
# ~/.claude/hooks/multi-agent-merge-discipline/pre-commit-strip-gen.sh and
# register a PreToolUse(Bash) entry pointing at $HOME (NOT $CLAUDE_PROJECT_DIR).
# The skill is opt-in per project via the presence of
# <project>/.claude/skills/multi-agent-merge-discipline/gen-paths.txt — the
# hook silent no-ops when the allowlist file is absent (line 80 of the script),
# so registering it globally is safe for projects that never adopt the skill.
#
# Drift recovery: v1.8.0 shipped without an install § here, so the hook got
# manually registered with command path `${CLAUDE_PROJECT_DIR}/.claude/skills/...`
# which fails on every Bash invocation outside a project that vendored the skill
# into .claude/skills/. Use the same matcher-aware canonicalization pattern as
# §13 (file-write-stale-stat-refusal) — drop any prior entry referencing the
# script (regardless of literal path) and add a fresh canonical entry.
log "Step 18: install multi-agent-merge-discipline"
MAMD_HOOK_SRC="$(cd "$GP_ROOT/.." && pwd)/multi-agent-merge-discipline/hooks/pre-commit-strip-gen.sh"
MAMD_HOOKS_DST="$CLAUDE_HOME/hooks/multi-agent-merge-discipline"
MAMD_HOOK_INSTALLED="$MAMD_HOOKS_DST/pre-commit-strip-gen.sh"
MAMD_MATCHER='Bash'

if [ ! -f "$MAMD_HOOK_SRC" ]; then
  log "  WARN: multi-agent-merge-discipline source missing at $MAMD_HOOK_SRC — skipping"
else
  do_or_dry mkdir -p "$MAMD_HOOKS_DST"
  do_or_dry cp "$MAMD_HOOK_SRC" "$MAMD_HOOK_INSTALLED"
  do_or_dry chmod +x "$MAMD_HOOK_INSTALLED"

  # Match by basename (pre-commit-strip-gen.sh) so we catch the broken
  # ${CLAUDE_PROJECT_DIR}/.claude/skills/multi-agent-merge-discipline/hooks/...
  # path AND any other prior literal — drift recovery is path-agnostic.
  if [ -f "$SETTINGS_DST" ] && command -v jq >/dev/null 2>&1; then
    PRESENT="$(jq --arg c "$MAMD_HOOK_INSTALLED" --arg m "$MAMD_MATCHER" \
      '[.hooks.PreToolUse[]? | select(.hooks[]?.command == $c) | select(.matcher == $m)] | length' \
      "$SETTINGS_DST" 2>/dev/null || echo 0)"
    # Also count any drifted entries (basename match, any matcher / any path).
    DRIFT_COUNT="$(jq '[.hooks.PreToolUse[]? | select(.hooks[]?.command | tostring | test("(^|/)pre-commit-strip-gen\\.sh$"))] | length' \
      "$SETTINGS_DST" 2>/dev/null || echo 0)"
    if [ "${PRESENT:-0}" -ge 1 ] && [ "${DRIFT_COUNT:-0}" -eq "${PRESENT:-0}" ]; then
      log "  $SETTINGS_DST already registers multi-agent-merge-discipline with canonical path+matcher (idempotent skip)"
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] register/canonicalize multi-agent-merge-discipline PreToolUse(Bash) hook\n'
      else
        BAK="$SETTINGS_DST.bak.mamd.$(date +%Y%m%d-%H%M%S)"
        cp "$SETTINGS_DST" "$BAK"
        TMP="$(mktemp)"
        # Drop ANY prior entry referencing pre-commit-strip-gen.sh (covers
        # the broken ${CLAUDE_PROJECT_DIR} literal + the canonical path),
        # then add a fresh canonical entry. matcher-rewrite, not duplicate.
        # Defensive: if removing the hook leaves an entry with no hooks,
        # drop the empty entry too.
        jq --arg cmd "$MAMD_HOOK_INSTALLED" --arg mat "$MAMD_MATCHER" '
          .hooks //= {}
          | .hooks.PreToolUse //= []
          | .hooks.PreToolUse |= map(
              .hooks |= map(select(
                (.command | tostring | test("(^|/)pre-commit-strip-gen\\.sh$")) | not
              ))
            )
          | .hooks.PreToolUse |= map(select((.hooks // []) | length > 0))
          | .hooks.PreToolUse += [{"matcher":$mat,"hooks":[{"type":"command","command":$cmd,"timeout":5000}]}]
        ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"
        log "  registered/canonicalized multi-agent-merge-discipline (backup: $BAK)"
      fi
    fi
  elif [ -f "$SETTINGS_DST" ]; then
    log "  WARN: jq missing — cannot canonicalize multi-agent-merge-discipline matcher; install with jq present to enable"
  fi
fi

log "DONE. Restart Claude Code or run /reload to pick up new settings."
exit 0
