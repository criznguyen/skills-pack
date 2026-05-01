#!/usr/bin/env bash
# schema-validate.sh — PreToolUse(*).
#
# Resolves the active skill (from frontmatter on disk, or from session cache)
# and validates tool_input against its declared `args_schema:`. Default
# behavior is advisory (decision=skip + telemetry log) when no schema is
# declared. Strict mode (~/.claude/typed-tool-surface.json mode=strict)
# treats missing/failing schemas as exit 2.
#
# Forbidden content (TM4): no LLM-spawn literals.
#
# Performance (Finding-S8-1 Cycle-1 remediation): the entire stdin parse +
# schema-cache lookup + JSON-Schema validate runs in a SINGLE python3
# invocation (was 4 separate invocations pre-Cycle-1). The script emits one
# US-separated line (ASCII 0x1F) consumed by `read` on the bash side. Re-bench:
# ~30 ms p50 with-schema-loaded (down from ~129 ms; 4x speedup).

set -uo pipefail

case "${TYPED_TOOL_SURFACE_DISABLE:-0}" in 1|true|TRUE|yes|YES) exit 0 ;; esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

HOME_DIR="${HOME:-/root}"
TTS_CONF="${TYPED_TOOL_SURFACE_CONF:-$HOME_DIR/.claude/typed-tool-surface.json}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null || exit 0

# Mode: advisory (default) or strict. (Cheap jq lookup; one syscall.)
MODE="advisory"
if [ -f "$TTS_CONF" ] && command -v jq >/dev/null 2>&1; then
  M="$(jq -r '.mode // "advisory"' "$TTS_CONF" 2>/dev/null || echo)"
  case "$M" in advisory|strict) MODE="$M" ;; esac
fi

if ! command -v python3 >/dev/null 2>&1; then
  # No python3 available — silently skip; we can't validate without it.
  exit 0
fi

# --- Single python3 invocation ------------------------------------------
# Parses stdin, locates the schema cache via $TTS_CACHE_BASE/<sid>/skill-schemas.json,
# performs JSON-Schema-lite validation (required, type, additionalProperties:false),
# and prints exactly one US-separated line (ASCII 0x1F unit separator):
#   tool_name<US>session_id<US>skill_name<US>decision<US>violations_json
# Decisions: pass | fail-validation | skip-no-skill | skip-no-schema.
# US is non-whitespace so bash `read` preserves empty fields (e.g. empty
# skill_name on the skip-no-skill path); tab would be collapsed.
RESULT_LINE="$(printf '%s' "$INPUT" \
  | TTS_CACHE_BASE="$HOME_DIR/.claude/sessions" \
    python3 -c '
import json, os, sys

US = "\x1f"

def emit(tn, sid, sk, decision, violations):
    # Sanitize the unit-separator (US) and newlines out of identifiers.
    def s(x): return str(x).replace(US, " ").replace("\n", " ")
    print(f"{s(tn)}{US}{s(sid)}{US}{s(sk)}{US}{decision}{US}{json.dumps(violations)}")
    sys.exit(0)

try:
    d = json.load(sys.stdin)
except Exception:
    emit("", "default", "", "skip-no-skill", [])

tool_name = d.get("tool_name") or ""
session_id = d.get("session_id") or "default"
tool_input = d.get("tool_input") or {}
skill_name = d.get("skill") or ""

if not skill_name:
    emit(tool_name, session_id, "", "skip-no-skill", [])

# Schema-cache lookup (was a separate jq syscall pre-Cycle-1).
cache_path = os.path.join(os.environ.get("TTS_CACHE_BASE", ""), session_id, "skill-schemas.json")
schema = None
try:
    with open(cache_path) as fh:
        cache = json.load(fh)
    if isinstance(cache, dict):
        schema = cache.get(skill_name)
except Exception:
    schema = None

if not isinstance(schema, dict):
    emit(tool_name, session_id, skill_name, "skip-no-schema", ["no-schema-declared"])

# JSON-Schema-lite validation.
violations = []
required = schema.get("required") or []
if isinstance(tool_input, dict):
    for r in required:
        if r not in tool_input:
            violations.append(f"/{r} required")
props = schema.get("properties") or {}
type_fns = {
    "string":  lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number":  lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "object":  lambda v: isinstance(v, dict),
    "array":   lambda v: isinstance(v, list),
}
if isinstance(tool_input, dict):
    for k, v in tool_input.items():
        spec = props.get(k)
        if not isinstance(spec, dict):
            continue
        t = spec.get("type")
        check = type_fns.get(t)
        if check and not check(v):
            violations.append(f"/{k} expected-type-{t}")
if schema.get("additionalProperties") is False and isinstance(tool_input, dict):
    allowed = set(props.keys())
    for k in tool_input.keys():
        if k not in allowed:
            violations.append(f"/{k} additional-property-forbidden")

if violations:
    emit(tool_name, session_id, skill_name, "fail-validation", violations)
emit(tool_name, session_id, skill_name, "pass", [])
' 2>/dev/null)"

if [ -z "$RESULT_LINE" ]; then
  exit 0
fi

# Bash-side: parse the single output line.
TOOL_NAME=""
SESSION_ID=""
SKILL_NAME=""
DECISION=""
VIOLATIONS_JSON="[]"
IFS=$'\x1f' read -r TOOL_NAME SESSION_ID SKILL_NAME DECISION VIOLATIONS_JSON <<< "$RESULT_LINE"
[ -z "$VIOLATIONS_JSON" ] && VIOLATIONS_JSON="[]"

emit_telemetry() {
  local decision="$1" violations="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"event":"schema-validate","ts":"%s","tool":"%s","decision":"%s","skill":"%s","violations":%s,"session_id":"%s"}\n' \
    "$ts" \
    "${TOOL_NAME//\"/}" \
    "${decision//\"/}" \
    "${SKILL_NAME//\"/}" \
    "$violations" \
    "${SESSION_ID//\"/}" \
    >> "$TELEM_FILE" 2>/dev/null || true
}

case "$DECISION" in
  pass)
    emit_telemetry "pass" "$VIOLATIONS_JSON"
    exit 0
    ;;
  skip-no-skill)
    emit_telemetry "skip" "$VIOLATIONS_JSON"
    exit 0
    ;;
  skip-no-schema)
    if [ "$MODE" = "strict" ]; then
      emit_telemetry "fail" "$VIOLATIONS_JSON"
      printf '[schema-validate] strict-mode: skill=%s has no declared args_schema; refusing\n' \
        "$SKILL_NAME" >&2
      exit 2
    fi
    emit_telemetry "skip" "$VIOLATIONS_JSON"
    exit 0
    ;;
  fail-validation)
    emit_telemetry "fail" "$VIOLATIONS_JSON"
    printf '[schema-validate] tool=%s skill=%s violations=%s\n' \
      "$TOOL_NAME" "$SKILL_NAME" "$VIOLATIONS_JSON" >&2
    if [ "$MODE" = "strict" ]; then
      exit 2
    fi
    exit 0
    ;;
  *)
    # Unknown decision token — fail-soft.
    exit 0
    ;;
esac
