#!/usr/bin/env bash
set -euo pipefail

# core-config / blast-radius
# PreToolUse hook for Bash. Inspects tool_input.command and either:
#   exit 2 (BLOCK)     — irrecoverable destructive ops
#   exit 2 (ESCALATE)  — risky ops that require explicit user re-confirmation
#   exit 0             — pass-through
# stderr is read by the model; the prefix differentiates BLOCK vs ESCALATE.

INPUT="$(cat 2>/dev/null || true)"
if [[ -z "${INPUT}" ]]; then
  echo "[blast-radius] empty stdin; skipping" >&2
  exit 0
fi

tool_name="$(printf '%s' "${INPUT}" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
if [[ "${tool_name}" != "Bash" ]]; then
  exit 0
fi

cmd="$(printf '%s' "${INPUT}" \
  | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"[[:space:]]*}.*/\1/p' \
  | head -n1)"
if [[ -z "${cmd}" ]]; then
  cmd="$(printf '%s' "${INPUT}" \
    | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n1 | sed 's/.*:"//; s/"$//')"
fi
if [[ -z "${cmd}" ]]; then
  echo "[blast-radius] could not parse command; passing through" >&2
  exit 0
fi

block() {
  printf '[blast-radius] BLOCK — %s\n' "$1" >&2
  printf '[blast-radius] Command: %s\n' "${cmd}" >&2
  exit 2
}

escalate() {
  printf '[blast-radius] ESCALATE — %s\n' "$1" >&2
  printf '[blast-radius] Command: %s\n' "${cmd}" >&2
  echo "[blast-radius] Surface this to the user and obtain explicit ack before proceeding." >&2
  exit 2
}

# --- BLOCK class -----------------------------------------------------------

RM_FLAGS='-[a-zA-Z]*[rRfF][a-zA-Z]*'
RM_PREFIX="(^|[[:space:];&|])rm[[:space:]]+(${RM_FLAGS}[[:space:]]+)+"
RM_ROOT_RE="${RM_PREFIX}/([[:space:];&|]|\$)"
RM_HOME_RE="${RM_PREFIX}(~|\\\$HOME|/home/[^[:space:]/]+)([[:space:]]|\$)"

if printf '%s' "${cmd}" | grep -qE "${RM_ROOT_RE}"; then
  block "rm -rf against root (/)"
fi
if printf '%s' "${cmd}" | grep -qE "${RM_HOME_RE}"; then
  block "rm -rf against \$HOME"
fi
if printf '%s' "${cmd}" | grep -qE 'git[[:space:]]+push[[:space:]].*(--force|-f([[:space:]]|$))' \
   && printf '%s' "${cmd}" | grep -qE '(^|[[:space:]:/])(main|master)([[:space:]]|$|:)'; then
  block "git push --force targeting main/master"
fi
if printf '%s' "${cmd}" | grep -qE 'git[[:space:]]+reset[[:space:]]+(--hard|--mixed[[:space:]]+--hard)'; then
  if git -C "${CLAUDE_PROJECT_DIR:-${PWD}}" status --porcelain 2>/dev/null | grep -q .; then
    block "git reset --hard with uncommitted/untracked changes in working tree"
  fi
fi

# --- ESCALATE class --------------------------------------------------------

if printf '%s' "${cmd}" | grep -qE '(^|[[:space:];&|=])sudo([[:space:]]|$)'; then
  escalate "sudo invocation"
fi
if printf '%s' "${cmd}" | grep -qE '(^|[[:space:]"=])/etc/'; then
  escalate "path under /etc/"
fi
if printf '%s' "${cmd}" | grep -qE '(^|[[:space:];&|])kubectl[[:space:]]+delete([[:space:]]|$)'; then
  escalate "kubectl delete"
fi

exit 0
