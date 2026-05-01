#!/usr/bin/env bash
set -euo pipefail

# core-config / anti-fantasy
# Stop hook. Scans the last assistant message in the transcript for unverified-claim
# language and either warns (default) or blocks (CORE_CONFIG_ANTI_FANTASY_STRICT=1).
# Exit 0 + stderr  = warn (transcript surfaces to model, no revision forced).
# Exit 2 + stderr  = block (Stop hook blocks; model must continue and revise).

INPUT="$(cat 2>/dev/null || true)"
if [[ -z "${INPUT}" ]]; then
  echo "[anti-fantasy] empty stdin; skipping" >&2
  exit 0
fi

transcript_path="$(printf '%s' "${INPUT}" \
  | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -n1)"
if [[ -z "${transcript_path}" || ! -r "${transcript_path}" ]]; then
  echo "[anti-fantasy] transcript unreadable; skipping" >&2
  exit 0
fi

last_assistant="$(awk '
  /"role"[[:space:]]*:[[:space:]]*"assistant"/ { last = $0 }
  END { if (last != "") print last }
' "${transcript_path}" 2>/dev/null || true)"

if [[ -z "${last_assistant}" ]]; then
  echo "[anti-fantasy] no assistant turn in transcript; skipping" >&2
  exit 0
fi

PATTERN='should work|I think|should be fine|probably works|appears to|looks like it works'

matches="$(printf '%s' "${last_assistant}" | grep -ioE "${PATTERN}" | sort -u || true)"

if [[ -z "${matches}" ]]; then
  exit 0
fi

count="$(printf '%s\n' "${matches}" | wc -l | tr -d ' ')"
strict="${CORE_CONFIG_ANTI_FANTASY_STRICT:-0}"

{
  echo "[anti-fantasy] ${count} unverified-claim phrase(s) detected in last assistant turn:"
  while IFS= read -r line; do
    [[ -z "${line}" ]] || printf '  - %s\n' "${line}"
  done <<< "${matches}"
  echo "[anti-fantasy] Replace with verified claims (read the file, run --help, grep the symbol)"
  echo "[anti-fantasy] or with explicit \"I don't know\" per CLAUDE.md §1."
} >&2

if [[ "${strict}" == "1" ]]; then
  exit 2
fi
exit 0
