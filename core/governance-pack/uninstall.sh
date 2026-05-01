#!/usr/bin/env bash
# uninstall.sh — reverses install.sh.
#
# Behavior:
#   - Removes ~/.claude/hooks/governance-pack/ directory.
#   - Restores latest ~/.claude/settings.json.bak.* (if present) on confirmation.
#   - Leaves ~/.claude/prod-paths.txt in place by default (user data; --purge to remove).
#   - Leaves ~/.claude/postconditions.d/ + postconditions.json in place by default
#     (operator data; --purge to remove). feat:postcondition-hook.
#   - Leaves project .claude/freeze.json in place by default (--purge to remove).
#
# Usage:
#   ./uninstall.sh              # remove hooks + offer to restore settings
#   ./uninstall.sh --purge      # also remove prod-paths.txt + project freeze.json
#   ./uninstall.sh --force      # non-interactive
#   ./uninstall.sh --project    # also clean project .claude/settings.local.json
#
# Exit codes: 0 success · 1 user abort · 2 nothing to remove.

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
HOOKS_DST="$CLAUDE_HOME/hooks/governance-pack"
SETTINGS_DST="$CLAUDE_HOME/settings.json"
PROD_PATHS_DST="$CLAUDE_HOME/prod-paths.txt"

PURGE=0
FORCE=0
PROJECT_MODE=0
# feat:quarantine-pack — remove the wrap-mcp-output hook entry + dir.
# --quarantine-only restricts uninstall to the quarantine-pack surface
# (skip governance-pack hooks dir + settings restore). --quarantine-purge
# additionally removes operator-owned ~/.claude/quarantine.{d,json}.
QUARANTINE_ONLY=0
QUARANTINE_PURGE=0

for arg in "$@"; do
  case "$arg" in
    --purge)             PURGE=1 ;;
    --force)             FORCE=1 ;;
    --project)           PROJECT_MODE=1 ;;
    --quarantine-only)   QUARANTINE_ONLY=1 ;;
    --quarantine-purge)  QUARANTINE_ONLY=1; QUARANTINE_PURGE=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '[uninstall] %s\n' "$*"; }
confirm() {
  [ "$FORCE" -eq 1 ] && return 0
  printf '%s [y/N] ' "$1"
  read -r reply
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# --- 0. Quarantine-pack uninstall (feat:quarantine-pack) -----------------
# Always runs (Steps 1-3 below skip when --quarantine-only). Removes the
# wrap-mcp-output PostToolUse entry from settings.json + the quarantine-pack
# hooks dir. Operator-owned data (~/.claude/quarantine.d, quarantine.json)
# is preserved unless --quarantine-purge.
QP_HOOKS_DST="$CLAUDE_HOME/hooks/quarantine-pack"
QP_DIR_DST="$CLAUDE_HOME/quarantine.d"
QP_CONF_DST="$CLAUDE_HOME/quarantine.json"

if [ -d "$QP_HOOKS_DST" ]; then
  log "Removing $QP_HOOKS_DST (quarantine-pack hook + library + template)"
  rm -rf "$QP_HOOKS_DST"
else
  log "No quarantine-pack hooks dir at $QP_HOOKS_DST"
fi

if [ -f "$SETTINGS_DST" ] && grep -q 'wrap-mcp-output' "$SETTINGS_DST" 2>/dev/null; then
  if command -v jq >/dev/null 2>&1; then
    BAK="$SETTINGS_DST.bak.quarantine.uninstall.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_DST" "$BAK"
    TMP="$(mktemp)"
    if jq '
      if .hooks.PostToolUse then
        .hooks.PostToolUse |= map(
          select(
            (.hooks // []) as $hs
            | ($hs | map(.command // "" | test("wrap-mcp-output")) | any) | not
          )
        )
      else . end
    ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"; then
      log "De-registered wrap-mcp-output from $SETTINGS_DST (backup: $BAK)"
    else
      log "WARN: jq de-register failed; settings.json unchanged at $SETTINGS_DST"
    fi
  else
    log "WARN: jq missing — cannot de-register wrap-mcp-output from $SETTINGS_DST"
    log "      Manually drop the PostToolUse entry whose command points at wrap-mcp-output.sh"
  fi
fi

if [ "$QUARANTINE_PURGE" -eq 1 ]; then
  if [ -d "$QP_DIR_DST" ]; then
    if confirm "Remove $QP_DIR_DST (trusted-MCP allowlist + operator edits)?"; then
      rm -rf "$QP_DIR_DST"
    fi
  fi
  if [ -f "$QP_CONF_DST" ]; then
    if confirm "Remove $QP_CONF_DST (mode config)?"; then
      rm -f "$QP_CONF_DST"
    fi
  fi
fi

if [ "$QUARANTINE_ONLY" -eq 1 ]; then
  log "DONE (--quarantine-only). Restart Claude Code to pick up changes."
  exit 0
fi

# --- 0h. sandbox-default-on uninstall (does NOT auto-rollback the flag) ---
SBX_DIR_DST="$CLAUDE_HOME/sandbox-default-on"
if [ -d "$SBX_DIR_DST" ]; then
  log "Removing $SBX_DIR_DST (sandbox-default-on staged files)"
  rm -rf "$SBX_DIR_DST"
fi
# NOTE: the operator must explicitly roll back permissions.defaultMode to "default"
# per templates/sandbox-rollback.md. We do NOT auto-flip back — that would be
# destructive and bypass the operator's deliberate decision to enable sandbox.
if [ -f "$SETTINGS_DST" ] && command -v jq >/dev/null 2>&1; then
  CURMODE="$(jq -r '.permissions.defaultMode // "default"' "$SETTINGS_DST" 2>/dev/null || echo)"
  if [ "$CURMODE" = "sandbox" ]; then
    log "NOTE: ~/.claude/settings.json still has permissions.defaultMode=sandbox"
    log "      To roll back: see core/sandbox-default-on/templates/sandbox-rollback.md"
  fi
fi

# --- 0g. typed-tool-surface uninstall -------------------------------------
TTS_HOOKS_DST="$CLAUDE_HOME/hooks/typed-tool-surface"
if [ -d "$TTS_HOOKS_DST" ]; then
  log "Removing $TTS_HOOKS_DST"
  rm -rf "$TTS_HOOKS_DST"
fi
if [ -f "$SETTINGS_DST" ] && grep -q 'schema-validate' "$SETTINGS_DST" 2>/dev/null; then
  if command -v jq >/dev/null 2>&1; then
    BAK="$SETTINGS_DST.bak.tts.uninstall.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_DST" "$BAK"
    TMP="$(mktemp)"
    if jq '
      if .hooks.PreToolUse then
        .hooks.PreToolUse |= map(
          select(((.hooks // []) | map(.command // "" | test("schema-validate")) | any) | not)
        )
      else . end
    ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"; then
      log "De-registered typed-tool-surface (backup: $BAK)"
    fi
  fi
fi

# --- 0f. loop-circuit-breaker uninstall -----------------------------------
LCB_HOOKS_DST="$CLAUDE_HOME/hooks/loop-circuit-breaker"
if [ -d "$LCB_HOOKS_DST" ]; then
  log "Removing $LCB_HOOKS_DST"
  rm -rf "$LCB_HOOKS_DST"
fi
if [ -f "$SETTINGS_DST" ] && grep -qE '(pretooluse-count-hash|posttooluse-cost|stop-summary)' "$SETTINGS_DST" 2>/dev/null; then
  if command -v jq >/dev/null 2>&1; then
    BAK="$SETTINGS_DST.bak.lcb.uninstall.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_DST" "$BAK"
    TMP="$(mktemp)"
    if jq '
      def strip(arr): arr | map(
        select(((.hooks // []) | map(.command // "" | test("pretooluse-count-hash|posttooluse-cost|stop-summary")) | any) | not)
      );
      .hooks.PreToolUse  |= (if . then strip(.) else . end)
      | .hooks.PostToolUse |= (if . then strip(.) else . end)
      | .hooks.Stop        |= (if . then strip(.) else . end)
    ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"; then
      log "De-registered loop-circuit-breaker (backup: $BAK)"
    fi
  fi
fi

# --- 0e. file-write-stale-stat-refusal uninstall --------------------------
FWS_HOOKS_DST="$CLAUDE_HOME/hooks/file-write-stale-stat-refusal"
if [ -d "$FWS_HOOKS_DST" ]; then
  log "Removing $FWS_HOOKS_DST"
  rm -rf "$FWS_HOOKS_DST"
fi
if [ -f "$SETTINGS_DST" ] && grep -qE '(file-stat-check|cache-mtime-on-read)' "$SETTINGS_DST" 2>/dev/null; then
  if command -v jq >/dev/null 2>&1; then
    BAK="$SETTINGS_DST.bak.fws.uninstall.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_DST" "$BAK"
    TMP="$(mktemp)"
    if jq '
      def strip(arr): arr | map(
        select(((.hooks // []) | map(.command // "" | test("file-stat-check|cache-mtime-on-read")) | any) | not)
      );
      .hooks.PreToolUse  |= (if . then strip(.) else . end)
      | .hooks.PostToolUse |= (if . then strip(.) else . end)
    ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"; then
      log "De-registered file-write-stale-stat-refusal hooks (backup: $BAK)"
    fi
  fi
fi

# --- 0d. hardcoded-credential-refusal uninstall ---------------------------
HCR_HOOKS_DST="$CLAUDE_HOME/hooks/hardcoded-credential-refusal"
if [ -d "$HCR_HOOKS_DST" ]; then
  log "Removing $HCR_HOOKS_DST"
  rm -rf "$HCR_HOOKS_DST"
fi
if [ -f "$SETTINGS_DST" ] && grep -q 'credential-scan' "$SETTINGS_DST" 2>/dev/null; then
  if command -v jq >/dev/null 2>&1; then
    BAK="$SETTINGS_DST.bak.hcr.uninstall.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_DST" "$BAK"
    TMP="$(mktemp)"
    if jq '
      if .hooks.PreToolUse then
        .hooks.PreToolUse |= map(
          select(((.hooks // []) | map(.command // "" | test("credential-scan")) | any) | not)
        )
      else . end
    ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"; then
      log "De-registered credential-scan from $SETTINGS_DST (backup: $BAK)"
    fi
  fi
fi

# --- 0c. git-force-push-gate uninstall ------------------------------------
GFP_HOOKS_DST="$CLAUDE_HOME/hooks/git-force-push-gate"
if [ -d "$GFP_HOOKS_DST" ]; then
  log "Removing $GFP_HOOKS_DST"
  rm -rf "$GFP_HOOKS_DST"
fi
if [ -f "$SETTINGS_DST" ] && grep -q 'git-push-gate' "$SETTINGS_DST" 2>/dev/null; then
  if command -v jq >/dev/null 2>&1; then
    BAK="$SETTINGS_DST.bak.gfp.uninstall.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_DST" "$BAK"
    TMP="$(mktemp)"
    if jq '
      if .hooks.PreToolUse then
        .hooks.PreToolUse |= map(
          select(((.hooks // []) | map(.command // "" | test("git-push-gate")) | any) | not)
        )
      else . end
    ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"; then
      log "De-registered git-push-gate from $SETTINGS_DST (backup: $BAK)"
    fi
  fi
fi

# --- 0b. recovery-class-fragment uninstall (opt-in skill) -----------------
# Remove the staged hooks dir if present; operator may also have wired a
# PostToolUse matcher pointing at recovery-classify.sh. Best-effort
# de-register that entry too (idempotent grep+jq).
RC_HOOKS_DST="$CLAUDE_HOME/hooks/recovery-class-fragment"
if [ -d "$RC_HOOKS_DST" ]; then
  log "Removing $RC_HOOKS_DST (recovery-class-fragment opt-in hook)"
  rm -rf "$RC_HOOKS_DST"
fi
if [ -f "$SETTINGS_DST" ] && grep -q 'recovery-classify' "$SETTINGS_DST" 2>/dev/null; then
  if command -v jq >/dev/null 2>&1; then
    BAK="$SETTINGS_DST.bak.recovery.uninstall.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_DST" "$BAK"
    TMP="$(mktemp)"
    if jq '
      if .hooks.PostToolUse then
        .hooks.PostToolUse |= map(
          select(
            (.hooks // []) as $hs
            | ($hs | map(.command // "" | test("recovery-classify")) | any) | not
          )
        )
      else . end
    ' "$SETTINGS_DST" > "$TMP" && mv "$TMP" "$SETTINGS_DST"; then
      log "De-registered recovery-classify from $SETTINGS_DST (backup: $BAK)"
    fi
  fi
fi

# --- 1. Remove hook scripts ----------------------------------------------
if [ -d "$HOOKS_DST" ]; then
  log "Removing $HOOKS_DST"
  rm -rf "$HOOKS_DST"
else
  log "No governance-pack hooks dir at $HOOKS_DST"
fi

# --- 2. Restore latest settings.json backup if available ----------------
LATEST_BAK="$(ls -1t "${SETTINGS_DST}".bak.* 2>/dev/null | head -n1 || true)"
if [ -n "$LATEST_BAK" ] && [ -f "$LATEST_BAK" ]; then
  if confirm "Restore $SETTINGS_DST from $LATEST_BAK?"; then
    cp "$LATEST_BAK" "$SETTINGS_DST"
    log "Restored $SETTINGS_DST from $LATEST_BAK"
  else
    log "Skipped restore — settings.json unchanged. Manual cleanup: remove governance-pack"
    log "  entries from \"hooks\" object and any \"deny\"/\"allow\" entries you do not want."
  fi
else
  log "No backup found — settings.json untouched. Manually remove governance-pack entries:"
  log "  hooks: paths under '\$HOME/.claude/hooks/governance-pack/' "
  log "  permissions.deny: any rule you no longer want"
fi

# --- 3. Optional purge of user data -------------------------------------
if [ "$PURGE" -eq 1 ]; then
  if [ -f "$PROD_PATHS_DST" ]; then
    log "Removing $PROD_PATHS_DST"
    rm -f "$PROD_PATHS_DST"
  fi
  if [ -f "$CLAUDE_HOME/telemetry.jsonl" ]; then
    if confirm "Remove $CLAUDE_HOME/telemetry.jsonl (local telemetry log)?"; then
      rm -f "$CLAUDE_HOME/telemetry.jsonl"
    fi
  fi
  # feat:postcondition-hook — purge operator-owned table + config.
  if [ -d "$CLAUDE_HOME/postconditions.d" ]; then
    if confirm "Remove $CLAUDE_HOME/postconditions.d/ (postcondition table + operator edits)?"; then
      rm -rf "$CLAUDE_HOME/postconditions.d"
    fi
  fi
  if [ -f "$CLAUDE_HOME/postconditions.json" ]; then
    if confirm "Remove $CLAUDE_HOME/postconditions.json (mode + timeout config)?"; then
      rm -f "$CLAUDE_HOME/postconditions.json"
    fi
  fi
fi

# --- 4. Project mode ----------------------------------------------------
if [ "$PROJECT_MODE" -eq 1 ]; then
  PROJ="$PWD/.claude"
  if [ -d "$PROJ" ]; then
    LATEST_PBAK="$(ls -1t "$PROJ/settings.local.json".bak.* 2>/dev/null | head -n1 || true)"
    if [ -n "$LATEST_PBAK" ]; then
      if confirm "Restore $PROJ/settings.local.json from $LATEST_PBAK?"; then
        cp "$LATEST_PBAK" "$PROJ/settings.local.json"
      fi
    fi
    if [ "$PURGE" -eq 1 ] && [ -f "$PROJ/freeze.json" ]; then
      if confirm "Remove $PROJ/freeze.json?"; then rm -f "$PROJ/freeze.json"; fi
    fi
  fi
fi

log "DONE. Restart Claude Code to pick up changes."
exit 0
