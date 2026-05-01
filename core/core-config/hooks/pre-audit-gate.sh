#!/usr/bin/env bash
set -euo pipefail

# core-config / pre-audit-gate
# PreToolUse hook on Task (sub-agent spawn). Blocks audit invocations against
# implementations that still contain stub markers — TODO, FIXME, XXX, "pass # placeholder",
# "not implemented". This prevents auditing code that isn't actually finished.
# Scope: files in `git diff <BASE>...HEAD --name-only` (default BASE=main); falls back
# to tracked files under src/ if no base is reachable.
#
# Override scan scope via CORE_CONFIG_AUDIT_SCOPE (space-separated paths/globs).
# Disable entirely via CORE_CONFIG_AUDIT_GATE=0.

if [[ "${CORE_CONFIG_AUDIT_GATE:-1}" == "0" ]]; then
  exit 0
fi

INPUT="$(cat 2>/dev/null || true)"
if [[ -z "${INPUT}" ]]; then
  exit 0
fi

tool_name="$(printf '%s' "${INPUT}" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
if [[ "${tool_name}" != "Task" && "${tool_name}" != "Agent" ]]; then
  exit 0
fi

# Match audit invocations: subagent_type=audit, OR description/prompt contains "audit"
# in a sense consistent with §6 of CLAUDE.md (e.g. "security audit", "audit report").
audit_signal=0
if printf '%s' "${INPUT}" | grep -qiE '"subagent_type"[[:space:]]*:[[:space:]]*"[^"]*audit'; then
  audit_signal=1
fi
if printf '%s' "${INPUT}" | grep -qiE '"(description|prompt)"[[:space:]]*:[[:space:]]*"[^"]*\baudit\b'; then
  audit_signal=1
fi
if [[ "${audit_signal}" -eq 0 ]]; then
  exit 0
fi

repo_dir="${CLAUDE_PROJECT_DIR:-${PWD}}"
if ! git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[pre-audit-gate] not a git repo (${repo_dir}); skipping" >&2
  exit 0
fi

mapfile -t files < <(
  if [[ -n "${CORE_CONFIG_AUDIT_SCOPE:-}" ]]; then
    # shellcheck disable=SC2086
    git -C "${repo_dir}" ls-files -- ${CORE_CONFIG_AUDIT_SCOPE} 2>/dev/null || true
  else
    base="$(git -C "${repo_dir}" rev-parse --verify --quiet origin/main 2>/dev/null \
            || git -C "${repo_dir}" rev-parse --verify --quiet main 2>/dev/null \
            || git -C "${repo_dir}" rev-parse --verify --quiet origin/master 2>/dev/null \
            || git -C "${repo_dir}" rev-parse --verify --quiet master 2>/dev/null || true)"
    if [[ -n "${base}" ]]; then
      git -C "${repo_dir}" diff --name-only "${base}"...HEAD 2>/dev/null || true
    else
      git -C "${repo_dir}" ls-files -- 'src/*' 'lib/*' 'app/*' 2>/dev/null || true
    fi
  fi
)

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "[pre-audit-gate] empty scan scope; passing through" >&2
  exit 0
fi

PATTERN='\bTODO\b|\bFIXME\b|\bXXX\b|pass[[:space:]]*#[[:space:]]*placeholder|not[[:space:]]+implemented'

hits=""
for f in "${files[@]}"; do
  [[ -f "${repo_dir}/${f}" ]] || continue
  case "${f}" in
    *.lock|*.png|*.jpg|*.jpeg|*.gif|*.pdf|*.zip|*.tar|*.gz) continue ;;
  esac
  m="$(grep -nE "${PATTERN}" "${repo_dir}/${f}" 2>/dev/null | head -n3 || true)"
  if [[ -n "${m}" ]]; then
    hits+="${f}:"$'\n'"${m}"$'\n'
  fi
done

if [[ -z "${hits}" ]]; then
  exit 0
fi

{
  echo "[pre-audit-gate] BLOCK — implementation contains stub markers; audit refused."
  echo "[pre-audit-gate] Resolve every TODO/FIXME/XXX/placeholder/not-implemented before re-spawning."
  echo "[pre-audit-gate] First hits:"
  printf '%s' "${hits}" | head -n40
} >&2
exit 2
