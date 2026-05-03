#!/usr/bin/env bash
set -uo pipefail

# core-config / pre-edit-stash
# PreToolUse hook for Edit|Write|MultiEdit. INSURANCE stash of the worktree
# state of the file the agent is about to modify, so the operator can recover
# their pre-edit state via `git stash list` if the agent's edit is wrong.
#
# This is INSURANCE, not a gate. ALWAYS exits 0; never blocks. Skip cases
# (silent exit 0, no stash, no JSONL): empty file_path / file does not exist
# / not in git repo / .gitignored / outside worktree / file matches deny
# pattern (.env*, secrets/**, *.pem, *.key, id_rsa*) / file is clean.
#
# Side effect on stash: append one JSONL line to ~/.claude/state/pre-edit-stashes.jsonl.
# On git-stash failure: append JSONL line with `error` field; emit stderr
# advisory; STILL exit 0.
#
# Opt-out: PRE_EDIT_STASH_DISABLE={1,true,TRUE} → exit 0 silent regardless.
#
# No jq required (sed-based parse, matches blast-radius.sh style). No python3.

if [[ "${PRE_EDIT_STASH_DISABLE:-}" =~ ^(1|true|TRUE)$ ]]; then
  exit 0
fi

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

# Resolve to absolute path. realpath -m allows non-existent paths.
if command -v realpath >/dev/null 2>&1; then
  abs_path="$(realpath -m "${file_path}" 2>/dev/null || printf '%s' "${file_path}")"
else
  case "${file_path}" in
    /*) abs_path="${file_path}" ;;
    *)  abs_path="$(pwd)/${file_path}" ;;
  esac
fi

# Skip 2: file does not exist on disk (Write creating a new file)
[[ -f "${abs_path}" ]] || exit 0

# Skip 3: not inside a git repo
repo_root="$(git -C "$(dirname "${abs_path}")" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "${repo_root}" ]] || exit 0

# Skip 4: file is .gitignored
if git -C "${repo_root}" check-ignore -q "${abs_path}" 2>/dev/null; then
  exit 0
fi

# Skip 5: file outside repo's worktree
case "${abs_path}" in
  "${repo_root}"/*) ;;
  *) exit 0 ;;
esac

# Skip 6: file path matches deny pattern (defense-in-depth: never let secret
# content enter git stash refs)
basename_="$(basename -- "${abs_path}")"
rel_path="${abs_path#"${repo_root}"/}"
case "${basename_}" in
  .env|.env.*)       exit 0 ;;
  *.pem|*.key)       exit 0 ;;
  *.cert|*.crt|*.p12) exit 0 ;;
  id_rsa*)           exit 0 ;;
  id_ed25519*)       exit 0 ;;
  id_ecdsa*)         exit 0 ;;
  credentials.json)  exit 0 ;;
  .npmrc)            exit 0 ;;
  .dockercfg)        exit 0 ;;
  .pgpass)           exit 0 ;;
  .envrc)            exit 0 ;;
esac
case "${rel_path}" in
  secrets/*)         exit 0 ;;
  .aws/credentials*) exit 0 ;;
  .aws/config*)      exit 0 ;;
esac

# Skip 7: file is clean in BOTH worktree and index
if git -C "${repo_root}" diff --quiet -- "${abs_path}" 2>/dev/null \
   && git -C "${repo_root}" diff --cached --quiet -- "${abs_path}" 2>/dev/null; then
  exit 0
fi

# Stash. Build the message + path setup before any side-effecting call so
# the JSONL line is consistent regardless of stash success/failure.
ts_unix="$(date +%s)"
ts_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
stash_msg="claude-pre-edit-${ts_unix}-${basename_}"

state_dir="${HOME}/.claude/state"
mkdir -p "${state_dir}" 2>/dev/null || true
jsonl_path="${state_dir}/pre-edit-stashes.jsonl"

# Pure-shell JSON string escape. Handles \\, ", \n, \r, \t — sufficient for
# operator paths, basenames, session_ids, and ≤200-char git stderr snippets.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

stash_err_tmp="$(mktemp 2>/dev/null || printf '/tmp/pre-edit-stash.err.%s' "$$")"
if git -C "${repo_root}" stash push --keep-index --include-untracked --quiet \
     -m "${stash_msg}" -- "${abs_path}" 2>"${stash_err_tmp}"; then
  stash_ref="$(git -C "${repo_root}" rev-parse --verify --short stash@{0} 2>/dev/null || printf 'unknown')"
  if ! printf '{"ts":"%s","session":"%s","tool":"%s","file":"%s","stash_ref":"%s","stash_msg":"%s"}\n' \
        "${ts_iso}" \
        "$(json_escape "${session_id}")" \
        "$(json_escape "${tool_name}")" \
        "$(json_escape "${abs_path}")" \
        "$(json_escape "${stash_ref}")" \
        "$(json_escape "${stash_msg}")" \
        >> "${jsonl_path}" 2>/dev/null
  then
    echo "[pre-edit-stash] cannot write JSONL log to ${jsonl_path}" >&2
  fi
else
  err_raw="$(head -c 200 "${stash_err_tmp}" 2>/dev/null || printf '')"
  if ! printf '{"ts":"%s","session":"%s","tool":"%s","file":"%s","stash_ref":"unknown","stash_msg":"%s","error":"%s"}\n' \
        "${ts_iso}" \
        "$(json_escape "${session_id}")" \
        "$(json_escape "${tool_name}")" \
        "$(json_escape "${abs_path}")" \
        "$(json_escape "${stash_msg}")" \
        "$(json_escape "${err_raw}")" \
        >> "${jsonl_path}" 2>/dev/null
  then
    echo "[pre-edit-stash] cannot write JSONL log to ${jsonl_path}" >&2
  fi
  echo "[pre-edit-stash] git stash failed for ${abs_path} (advisory; exit 0)" >&2
fi

rm -f "${stash_err_tmp}" 2>/dev/null || true
exit 0
