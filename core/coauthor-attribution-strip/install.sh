#!/usr/bin/env bash
# install.sh — coauthor-attribution-strip standalone installer.
#
# Adds (or canonicalizes) `attribution.commit = ""` in
# $HOME/.claude/settings.json so the Claude Code harness strips
# Anthropic / Claude trailers from generated commit messages.
# Replaces prompt-only enforcement of the `feedback_no_claude_coauthor`
# rule with a first-party harness primitive.
#
# Behavior:
#   - Backs up settings.json before write (timestamped sibling).
#   - Idempotent: no change if canonical value already present.
#   - Drift recovery: rewrites stale `.attribution.commit` (any value)
#     to canonical "".
#   - Honors COAUTHOR_ATTRIBUTION_STRIP_DISABLE={1|true|yes} as opt-out.
#   - --dry-run: print plan, exit 0 without writing.
#
# Exit codes: 0 success / opt-out / dry-run · 2 prerequisite missing
#             3 merge failed.

set -uo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,21p' "$0"
      exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '[coauthor-attribution-strip/install] %s\n' "$*"; }

# --- 0. Opt-out check ----------------------------------------------------
case "${COAUTHOR_ATTRIBUTION_STRIP_DISABLE:-0}" in
  1|true|TRUE|True|yes|YES|Yes)
    log "COAUTHOR_ATTRIBUTION_STRIP_DISABLE is set — opt-out honored, no changes"
    exit 0
    ;;
esac

# --- 1. Prerequisites ----------------------------------------------------
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: need either jq or python3 to merge settings.json." >&2
  exit 2
fi

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SETTINGS_DST="$CLAUDE_HOME/settings.json"

# --- 2. Resolve current state --------------------------------------------
# We use a matcher-aware approach (same pattern as
# core/governance-pack/install.sh §13 / §18): inspect the existing
# .attribution.commit value via jq and only write if it is missing OR
# differs from the canonical empty string.
CANONICAL_VALUE=""
NEED_WRITE=0
CURRENT_VALUE_DESC="(absent)"

if [ ! -f "$SETTINGS_DST" ]; then
  # Fresh install: settings.json does not exist yet.
  NEED_WRITE=1
  CURRENT_VALUE_DESC="(file absent)"
else
  if command -v jq >/dev/null 2>&1; then
    # `jq -e` returns non-zero if the value is null / missing. Use a
    # boolean test for "field present and equals canonical empty
    # string" so missing AND non-empty both trigger write.
    HAS_FIELD="$(jq 'has("attribution") and (.attribution | type == "object") and (.attribution | has("commit"))' \
      "$SETTINGS_DST" 2>/dev/null || echo false)"
    if [ "$HAS_FIELD" = "true" ]; then
      CURRENT_RAW="$(jq -r '.attribution.commit' "$SETTINGS_DST" 2>/dev/null || echo)"
      CURRENT_VALUE_DESC="\"$CURRENT_RAW\""
      if [ "$CURRENT_RAW" = "$CANONICAL_VALUE" ]; then
        NEED_WRITE=0
      else
        NEED_WRITE=1
      fi
    else
      NEED_WRITE=1
    fi
  else
    # python3 fallback. Same logic.
    NEED_WRITE="$(python3 - "$SETTINGS_DST" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except Exception:
    print(1); sys.exit(0)
attr = d.get("attribution")
if not isinstance(attr, dict) or "commit" not in attr:
    print(1); sys.exit(0)
print(0 if attr.get("commit") == "" else 1)
PY
)"
    if [ "$NEED_WRITE" = "0" ]; then
      CURRENT_VALUE_DESC='""'
    else
      CURRENT_VALUE_DESC="(non-canonical or absent)"
    fi
  fi
fi

# --- 3. Idempotent skip --------------------------------------------------
if [ "$NEED_WRITE" -eq 0 ]; then
  log "$SETTINGS_DST already has canonical .attribution.commit=\"\" (idempotent skip)"
  exit 0
fi

# --- 4. Plan / dry-run ---------------------------------------------------
log "current .attribution.commit: $CURRENT_VALUE_DESC"
log "canonical target:              \"\""
if [ "$DRY_RUN" -eq 1 ]; then
  log "[dry-run] would write $SETTINGS_DST .attribution.commit=\"\" (with backup)"
  exit 0
fi

# --- 5. Ensure $CLAUDE_HOME exists, write canonical -----------------------
mkdir -p "$CLAUDE_HOME"

if [ ! -f "$SETTINGS_DST" ]; then
  # Fresh write: minimal skeleton with only our field.
  cat > "$SETTINGS_DST" <<'JSON'
{
  "attribution": {
    "commit": ""
  }
}
JSON
  log "wrote fresh $SETTINGS_DST with .attribution.commit=\"\""
  exit 0
fi

BAK="$SETTINGS_DST.bak.coauthor.$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS_DST" "$BAK" || { echo "ERROR: failed to back up $SETTINGS_DST" >&2; exit 3; }
log "backed up $SETTINGS_DST → $BAK"

TMP="$(mktemp)" || { echo "ERROR: mktemp failed" >&2; exit 3; }

if command -v jq >/dev/null 2>&1; then
  # Drop-then-set: ensure .attribution is an object, then assign
  # .attribution.commit="". Same matcher-aware shape as governance-pack
  # §13 (drop-then-add via jq, not duplicate-add).
  if ! jq '.attribution //= {} | .attribution.commit = ""' \
       "$SETTINGS_DST" > "$TMP"; then
    echo "ERROR: jq merge failed; original at $BAK" >&2
    rm -f "$TMP"
    exit 3
  fi
else
  # python3 fallback.
  if ! python3 - "$SETTINGS_DST" "$TMP" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    with open(src) as f:
        d = json.load(f)
except Exception as exc:
    sys.stderr.write("ERROR: parse %s: %s\n" % (src, exc))
    sys.exit(3)
attr = d.get("attribution")
if not isinstance(attr, dict):
    attr = {}
attr["commit"] = ""
d["attribution"] = attr
with open(dst, "w") as f:
    json.dump(d, f, indent=2)
PY
  then
    echo "ERROR: python3 merge failed; original at $BAK" >&2
    rm -f "$TMP"
    exit 3
  fi
fi

mv "$TMP" "$SETTINGS_DST"
log "wrote $SETTINGS_DST with .attribution.commit=\"\" (backup: $BAK)"
exit 0
