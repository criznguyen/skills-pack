#!/usr/bin/env bash
set -euo pipefail

# core-config installer. Idempotent: running twice produces no diff.
# Default target is ~/.claude/. Override with: TARGET=/path/to/.claude ./install.sh
# Source root is the directory of this script.
#
# Flags:
#   --force   skip the interactive prompt before merging settings.json
#   --dry-run print the planned diff and exit without modifying anything

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${TARGET:-${HOME}/.claude}"
FORCE=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --force)   FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '4,12p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "${TARGET}/hooks"

install_file() {
  local from="$1" to="$2" mode="$3"
  if [[ -f "${to}" ]] && cmp -s "${from}" "${to}"; then
    echo "  unchanged: ${to}"
  else
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "  [dry-run] would install: ${to}"
    else
      install -m "${mode}" "${from}" "${to}"
      echo "  installed: ${to}"
    fi
  fi
}

confirm() {
  [[ "${FORCE}" -eq 1 ]] && return 0
  local prompt="$1"
  printf '%s [y/N] ' "$prompt"
  read -r reply
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

merge_settings() {
  local from="$1" to="$2"
  if [[ ! -f "${to}" ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "  [dry-run] would install: ${to}"
    else
      install -m 0644 "${from}" "${to}"
      echo "  installed: ${to}"
    fi
    return
  fi
  if cmp -s "${from}" "${to}"; then
    echo "  unchanged: ${to}"
    return
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  WARN: python3 missing; cannot merge settings.json safely; leaving ${to} alone." >&2
    echo "  WARN: review ${from} and merge manually." >&2
    return
  fi

  # Compute the planned merge into a temp file (no in-place writes yet).
  local tmp
  tmp="$(mktemp)"
  if ! python3 - "${from}" "${to}" "${tmp}" <<'PY'
import json, sys, pathlib
src = json.loads(pathlib.Path(sys.argv[1]).read_text())
dst_path = pathlib.Path(sys.argv[2])
out_path = pathlib.Path(sys.argv[3])
dst = json.loads(dst_path.read_text()) if dst_path.exists() else {}

def merge(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        out = dict(a)
        for k, v in b.items():
            out[k] = merge(a.get(k), v) if k in a else v
        return out
    if isinstance(a, list) and isinstance(b, list):
        seen = [json.dumps(x, sort_keys=True) for x in a]
        out = list(a)
        for x in b:
            if json.dumps(x, sort_keys=True) not in seen:
                out.append(x)
        return out
    return b

merged = merge(dst, src)
out_path.write_text(json.dumps(merged, indent=2, sort_keys=False) + "\n")
PY
  then
    echo "  ERROR: merge computation failed for ${to}" >&2
    rm -f "${tmp}"
    return 1
  fi

  if cmp -s "${tmp}" "${to}"; then
    echo "  unchanged: ${to}"
    rm -f "${tmp}"
    return
  fi

  # Show planned diff to operator before any mutation.
  echo "  planned changes to ${to}:"
  if command -v diff >/dev/null 2>&1; then
    diff -u "${to}" "${tmp}" | sed 's/^/    /' >&2 || true
  else
    echo "    (diff unavailable; review ${tmp} manually)" >&2
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "  [dry-run] no changes written. Planned merge in: ${tmp}" >&2
    return
  fi

  if ! confirm "  Apply merge to ${to}?"; then
    echo "  user declined — ${to} unchanged."
    rm -f "${tmp}"
    return
  fi

  local bak
  bak="${to}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "${to}" "${bak}"
  echo "  backup:    ${bak}"
  mv "${tmp}" "${to}"
  echo "  merged:    ${to}"
}

echo "core-config installer"
echo "  source: ${SRC}"
echo "  target: ${TARGET}"

install_file "${SRC}/CLAUDE.md"               "${TARGET}/CLAUDE.md"               0644
install_file "${SRC}/hooks/anti-fantasy.sh"   "${TARGET}/hooks/anti-fantasy.sh"   0755
install_file "${SRC}/hooks/blast-radius.sh"   "${TARGET}/hooks/blast-radius.sh"   0755
install_file "${SRC}/hooks/pre-audit-gate.sh" "${TARGET}/hooks/pre-audit-gate.sh" 0755
merge_settings "${SRC}/settings.json"         "${TARGET}/settings.json"

echo "done."
