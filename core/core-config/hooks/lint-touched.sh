#!/usr/bin/env bash
set -uo pipefail

# core-config / lint-touched
# PostToolUse hook for Edit|Write|MultiEdit. PROJECT-level: installed at
# `${CLAUDE_PROJECT_DIR}/.claude/hooks/lint-touched.sh` via
# `core-config/install.sh --project <path>`, NOT at ~/.claude/.
#
# Runs the appropriate linter against the file the agent just touched:
#   .py                          → ruff (preferred) → flake8
#   .ts .tsx .js .jsx .mjs .cjs  → local node_modules/.bin/eslint (no global)
#   .rs                          → rustfmt --check (only if Cargo.toml in tree)
#   .sh .bash                    → shellcheck
#   .json                        → jq . > /dev/null
#
# Default: SHADOW-MODE (advisory + JSONL telemetry; exit 0 on linter fail).
# Promote to blocking via `LINT_TOUCHED_BLOCKING={1,true,TRUE}` (exit 2 on
# linter fail; stderr surfaces full linter output to the agent).
#
# Skip cases (silent exit 0, no JSONL): empty file_path / file no longer
# exists / extension not in lint table / linter binary not in PATH /
# per-language opt-out env / global opt-out LINT_TOUCHED_DISABLE.
#
# Telemetry sink: ~/.claude/telemetry.jsonl (joins existing telemetry stream
# from governance-pack/hooks/telemetry.sh).

is_truthy() {
  case "${1:-}" in 1|true|TRUE) return 0 ;; *) return 1 ;; esac
}

if is_truthy "${LINT_TOUCHED_DISABLE:-}"; then exit 0; fi

INPUT="$(cat 2>/dev/null || true)"
[[ -n "${INPUT}" ]] || exit 0

tool_name="$(printf '%s' "${INPUT}" \
  | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -n1)"
file_path="$(printf '%s' "${INPUT}" \
  | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 \
  | sed -e 's/^"file_path"[[:space:]]*:[[:space:]]*"//' -e 's/"$//')"
session_id="$(printf '%s' "${INPUT}" \
  | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -n1)"
[[ -z "${session_id}" ]] && session_id="unknown"
[[ -z "${tool_name}" ]] && tool_name="unknown"

# Skip 1: empty file_path
[[ -z "${file_path}" ]] && exit 0

# Resolve absolute path (-m allows non-existent paths so we still get a
# clean string even if the file was deleted between PostToolUse and now)
if command -v realpath >/dev/null 2>&1; then
  abs_path="$(realpath -m "${file_path}" 2>/dev/null || printf '%s' "${file_path}")"
else
  case "${file_path}" in
    /*) abs_path="${file_path}" ;;
    *)  abs_path="$(pwd)/${file_path}" ;;
  esac
fi

# Skip 2: file no longer exists on disk (deleted between hook fire and now)
[[ -f "${abs_path}" ]] || exit 0

ext="${abs_path##*.}"
ext="${ext,,}"  # lowercase for case match

linter=""
declare -a lint_argv=()
skip_env=""

case "${ext}" in
  py)
    skip_env="LINT_TOUCHED_SKIP_PY"
    if command -v ruff >/dev/null 2>&1; then
      linter="ruff"
      lint_argv=(ruff check "${abs_path}")
    elif command -v flake8 >/dev/null 2>&1; then
      linter="flake8"
      lint_argv=(flake8 "${abs_path}")
    fi
    ;;
  ts|tsx|js|jsx|mjs|cjs)
    skip_env="LINT_TOUCHED_SKIP_TS"
    # Walk up from file's dir looking for node_modules/.bin/eslint.
    local_eslint=""
    walker="$(dirname -- "${abs_path}")"
    while [[ -n "${walker}" && "${walker}" != "/" ]]; do
      if [[ -x "${walker}/node_modules/.bin/eslint" ]]; then
        local_eslint="${walker}/node_modules/.bin/eslint"
        break
      fi
      walker="$(dirname -- "${walker}")"
    done
    if [[ -n "${local_eslint}" ]]; then
      linter="eslint"
      lint_argv=("${local_eslint}" --no-error-on-unmatched-pattern "${abs_path}")
    fi
    ;;
  rs)
    skip_env="LINT_TOUCHED_SKIP_RS"
    # Only invoke rustfmt if Cargo.toml exists somewhere up the tree.
    has_cargo=""
    walker="$(dirname -- "${abs_path}")"
    while [[ -n "${walker}" && "${walker}" != "/" ]]; do
      if [[ -f "${walker}/Cargo.toml" ]]; then
        has_cargo="1"
        break
      fi
      walker="$(dirname -- "${walker}")"
    done
    if [[ -n "${has_cargo}" ]] && command -v rustfmt >/dev/null 2>&1; then
      linter="rustfmt"
      lint_argv=(rustfmt --check "${abs_path}")
    fi
    ;;
  sh|bash)
    skip_env="LINT_TOUCHED_SKIP_SH"
    if command -v shellcheck >/dev/null 2>&1; then
      linter="shellcheck"
      lint_argv=(shellcheck "${abs_path}")
    fi
    ;;
  json)
    skip_env="LINT_TOUCHED_SKIP_JSON"
    if command -v jq >/dev/null 2>&1; then
      linter="jq"
      lint_argv=(jq . "${abs_path}")
    fi
    ;;
  *)
    # Skip 3: extension not in lint table
    exit 0
    ;;
esac

# Skip 5: per-language opt-out
if [[ -n "${skip_env}" ]] && is_truthy "${!skip_env:-}"; then
  exit 0
fi

# Skip 4: linter binary not in PATH (after fallback chain exhausted)
if [[ -z "${linter}" ]]; then
  exit 0
fi

# Run the linter; capture combined stdout+stderr.
lint_out_tmp="$(mktemp 2>/dev/null || printf '/tmp/lint-touched.%s' "$$")"
if [[ "${linter}" = "jq" ]]; then
  # jq's success path writes to stdout; we don't care about it.
  "${lint_argv[@]}" >/dev/null 2>"${lint_out_tmp}"
  linter_exit=$?
else
  "${lint_argv[@]}" >"${lint_out_tmp}" 2>&1
  linter_exit=$?
fi

if [[ ${linter_exit} -eq 0 ]]; then
  rm -f "${lint_out_tmp}" 2>/dev/null || true
  exit 0
fi

# Linter failed. Mode determines block-vs-advise.
mode="shadow"
if is_truthy "${LINT_TOUCHED_BLOCKING:-}"; then
  mode="blocking"
fi

# Read combined output, truncate to 500 chars for telemetry.
out_full="$(cat "${lint_out_tmp}" 2>/dev/null || printf '')"
out_trunc="$(printf '%s' "${out_full}" | head -c 500)"
rm -f "${lint_out_tmp}" 2>/dev/null || true

ts_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

telemetry_dir="${HOME}/.claude"
mkdir -p "${telemetry_dir}" 2>/dev/null || true
telemetry_path="${telemetry_dir}/telemetry.jsonl"

if ! printf '{"event":"lint-touched","ts":"%s","tool":"%s","file":"%s","linter":"%s","status":"fail","exit":%d,"output":"%s","mode":"%s","session":"%s"}\n' \
      "${ts_iso}" \
      "$(json_escape "${tool_name}")" \
      "$(json_escape "${abs_path}")" \
      "$(json_escape "${linter}")" \
      "${linter_exit}" \
      "$(json_escape "${out_trunc}")" \
      "${mode}" \
      "$(json_escape "${session_id}")" \
      >> "${telemetry_path}" 2>/dev/null
then
  echo "[lint-touched] cannot write telemetry to ${telemetry_path}" >&2
fi

basename_lt="$(basename -- "${abs_path}")"
if [[ "${mode}" = "blocking" ]]; then
  {
    echo "[lint-touched] ${linter} failed for ${basename_lt} (blocking-mode, exit 2)"
    printf '%s\n' "${out_full}"
  } >&2
  exit 2
else
  echo "[lint-touched] ${linter} failed for ${basename_lt} (shadow-mode, exit 0)" >&2
  exit 0
fi
