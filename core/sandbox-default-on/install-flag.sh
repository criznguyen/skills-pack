#!/usr/bin/env bash
# install-flag.sh — flips ~/.claude/settings.json permissions.defaultMode to
# "sandbox". Idempotent: detects already-set state and emits action=already-set.
#
# Forbidden content (TM4): no LLM-spawn literals.

set -uo pipefail

HOME_DIR="${HOME:-/root}"
SETTINGS_DST="${SANDBOX_SETTINGS_DST:-$HOME_DIR/.claude/settings.json}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null

emit() {
  local action="$1" prev="$2" new="$3"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"event":"sandbox-default-on","ts":"%s","action":"%s","previous_mode":"%s","new_mode":"%s","session_id":"install-time"}\n' \
    "$ts" "$action" "${prev//\"/}" "${new//\"/}" \
    >> "$TELEM_FILE" 2>/dev/null || true
}

if [ ! -f "$SETTINGS_DST" ]; then
  printf '[sandbox-default-on] %s missing — run governance-pack/install.sh first\n' "$SETTINGS_DST" >&2
  emit "skipped" "" ""
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '[sandbox-default-on] jq required\n' >&2
  emit "skipped" "" ""
  exit 1
fi

PREV="$(jq -r '.permissions.defaultMode // "default"' "$SETTINGS_DST" 2>/dev/null)"
if [ "$PREV" = "sandbox" ]; then
  printf '[sandbox-default-on] already-set; no change\n' >&2
  emit "already-set" "$PREV" "sandbox"
  exit 0
fi

BAK="$SETTINGS_DST.bak.sandbox.$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS_DST" "$BAK"

TMP="$(mktemp)"
if jq '.permissions //= {} | .permissions.defaultMode = "sandbox"' "$SETTINGS_DST" > "$TMP" 2>/dev/null; then
  mv "$TMP" "$SETTINGS_DST"
  printf '[sandbox-default-on] enabled (previous=%s); backup=%s\n' "$PREV" "$BAK" >&2
  printf 'Rollback recipe: jq '"'"'.permissions.defaultMode = "default"'"'"' %s > /tmp/s && mv /tmp/s %s\n' "$SETTINGS_DST" "$SETTINGS_DST" >&2
  emit "enabled" "$PREV" "sandbox"
  exit 0
else
  rm -f "$TMP"
  printf '[sandbox-default-on] jq merge failed; original at %s\n' "$BAK" >&2
  emit "failed" "$PREV" ""
  exit 2
fi
