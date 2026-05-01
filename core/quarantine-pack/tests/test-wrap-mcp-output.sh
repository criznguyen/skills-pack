#!/usr/bin/env bash
# test-wrap-mcp-output.sh — unit tests for wrap-mcp-output.sh.
# Covers tech-spec §1.8 cases 1-10 plus the privacy invariant (AC6).
# Each case runs the hook against a synthetic stdin payload with HOME
# pointed at a fresh temp dir and asserts on stdout / stderr / JSONL line
# shape. Exits non-zero on any failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
HOOK="$REPO_ROOT/core/quarantine-pack/hooks/wrap-mcp-output.sh"
ALLOWLIST_SRC="$REPO_ROOT/core/quarantine-pack/templates/trusted-mcp-allowlist.txt"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf '  details: %s\n' "$2" >&2
}

# run_hook <input-json> → sets STDOUT, STDERR, RC, TELEM_LINES, TMP_HOME.
run_hook() {
  local input="$1"
  TMP_HOME="$(mktemp -d)"
  mkdir -p "$TMP_HOME/.claude/quarantine.d"
  cp "$ALLOWLIST_SRC" "$TMP_HOME/.claude/quarantine.d/trusted-mcp-allowlist.txt"
  local out_f err_f
  out_f="$(mktemp)"
  err_f="$(mktemp)"
  printf '%s' "$input" | HOME="$TMP_HOME" bash "$HOOK" >"$out_f" 2>"$err_f"
  RC=$?
  STDOUT="$(cat "$out_f")"
  STDERR="$(cat "$err_f")"
  TELEM_FILE="$TMP_HOME/.claude/telemetry.jsonl"
  if [ -f "$TELEM_FILE" ]; then
    TELEM_LINES="$(cat "$TELEM_FILE")"
  else
    TELEM_LINES=""
  fi
  rm -f "$out_f" "$err_f"
}

cleanup_run() {
  [ -n "${TMP_HOME:-}" ] && rm -rf "$TMP_HOME"
}

# --- Case 1: empty stdin → exit 0, no output ----------------------------
run_hook ""
if [ "$RC" -eq 0 ] && [ -z "$STDOUT" ] && [ ! -f "$TELEM_FILE" ]; then
  pass
else
  fail "case 1 empty stdin" "rc=$RC stdout='$STDOUT' telem='$TELEM_LINES'"
fi
cleanup_run

# --- Case 2: non-matching tool (Bash) → exit 0, no advisory -------------
run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"s2"}'
if [ "$RC" -eq 0 ] \
  && ! printf '%s' "$STDOUT" | grep -q hookSpecificOutput \
  && printf '%s' "$TELEM_LINES" | grep -q '"matcher_status":"skipped"' \
  && printf '%s' "$TELEM_LINES" | grep -q '"surface":"non_match"'; then
  pass
else
  fail "case 2 Bash" "stdout='$STDOUT' telem='$TELEM_LINES'"
fi
cleanup_run

# --- Case 3: untrusted mcp → tagged + advisory --------------------------
run_hook '{"tool_name":"mcp__zendesk__list_tickets","tool_input":{},"session_id":"s3"}'
if [ "$RC" -eq 0 ] \
  && printf '%s' "$STDOUT" | grep -q hookSpecificOutput \
  && printf '%s' "$STDOUT" | grep -q '\[QUARANTINE-NOTICE:' \
  && printf '%s' "$TELEM_LINES" | grep -q '"matcher_status":"tagged"' \
  && printf '%s' "$TELEM_LINES" | grep -q '"surface":"mcp_user_content"'; then
  pass
else
  fail "case 3 untrusted mcp" "stdout='$STDOUT' telem='$TELEM_LINES'"
fi
cleanup_run

# --- Case 4: trusted mcp → skipped, no advisory -------------------------
run_hook '{"tool_name":"mcp__linear_list_issues","tool_input":{},"session_id":"s4"}'
if [ "$RC" -eq 0 ] \
  && ! printf '%s' "$STDOUT" | grep -q hookSpecificOutput \
  && printf '%s' "$TELEM_LINES" | grep -q '"matcher_status":"skipped"' \
  && printf '%s' "$TELEM_LINES" | grep -q '"trusted_mcp":"mcp__linear"'; then
  pass
else
  fail "case 4 trusted mcp" "stdout='$STDOUT' telem='$TELEM_LINES'"
fi
cleanup_run

# --- Case 5: WebFetch → tagged regardless of domain ---------------------
run_hook '{"tool_name":"WebFetch","tool_input":{"url":"https://github.com/x/y"},"session_id":"s5"}'
if [ "$RC" -eq 0 ] \
  && printf '%s' "$STDOUT" | grep -q hookSpecificOutput \
  && printf '%s' "$TELEM_LINES" | grep -q '"surface":"web_fetch"' \
  && printf '%s' "$TELEM_LINES" | grep -q '"matcher_status":"tagged"'; then
  pass
else
  fail "case 5 WebFetch" "stdout='$STDOUT' telem='$TELEM_LINES'"
fi
cleanup_run

# --- Case 6: Read of non-upload path → skipped --------------------------
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/foo/bar.go"},"session_id":"s6"}'
if [ "$RC" -eq 0 ] \
  && ! printf '%s' "$STDOUT" | grep -q hookSpecificOutput \
  && printf '%s' "$TELEM_LINES" | grep -q '"matcher_status":"skipped"' \
  && printf '%s' "$TELEM_LINES" | grep -q '"surface":"non_upload_read"'; then
  pass
else
  fail "case 6 Read non-upload" "stdout='$STDOUT' telem='$TELEM_LINES'"
fi
cleanup_run

# --- Case 7: Read of /x/uploads/img.png → tagged ------------------------
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/x/uploads/img.png"},"session_id":"s7"}'
if [ "$RC" -eq 0 ] \
  && printf '%s' "$STDOUT" | grep -q hookSpecificOutput \
  && printf '%s' "$TELEM_LINES" | grep -q '"matcher_status":"tagged"' \
  && printf '%s' "$TELEM_LINES" | grep -q '"surface":"upload_read"'; then
  pass
else
  fail "case 7 Read upload" "stdout='$STDOUT' telem='$TELEM_LINES'"
fi
cleanup_run

# --- Case 8: privacy invariant — never logs tool_input/tool_response ---
run_hook '{"tool_name":"mcp__zendesk__list_tickets","tool_input":{"secret":"hunter2","password":"abcd"},"tool_response":{"body":"some text token=AAA"},"session_id":"s8"}'
if printf '%s' "$TELEM_LINES" | grep -E 'tool_input|tool_response|secret|password|hunter2|token=' >/dev/null; then
  fail "case 8 privacy" "telem leaked input/response: $TELEM_LINES"
else
  pass
fi
cleanup_run

# --- Case 9: jq missing, python3 present → still works ------------------
TMP_HOME="$(mktemp -d)"
mkdir -p "$TMP_HOME/.claude/quarantine.d"
cp "$ALLOWLIST_SRC" "$TMP_HOME/.claude/quarantine.d/trusted-mcp-allowlist.txt"
out_f="$(mktemp)"
err_f="$(mktemp)"
SHIM_DIR="$(mktemp -d)"
# Build a PATH that excludes jq but keeps python3 + coreutils.
# Symlink everything in /usr/bin and /bin EXCEPT jq into SHIM_DIR.
for d in /usr/bin /bin; do
  [ -d "$d" ] || continue
  for src in "$d"/*; do
    [ -e "$src" ] || continue
    base="$(basename "$src")"
    case "$base" in jq) continue ;; esac
    [ -e "$SHIM_DIR/$base" ] && continue
    ln -s "$src" "$SHIM_DIR/$base" 2>/dev/null || true
  done
done
printf '%s' '{"tool_name":"mcp__zendesk__list_tickets","tool_input":{},"session_id":"s9"}' \
  | HOME="$TMP_HOME" PATH="$SHIM_DIR" bash "$HOOK" >"$out_f" 2>"$err_f"
RC=$?
STDOUT="$(cat "$out_f")"
TELEM_LINES=""
[ -f "$TMP_HOME/.claude/telemetry.jsonl" ] && TELEM_LINES="$(cat "$TMP_HOME/.claude/telemetry.jsonl")"
if [ "$RC" -eq 0 ] \
  && printf '%s' "$STDOUT" | grep -q hookSpecificOutput \
  && printf '%s' "$TELEM_LINES" | grep -q '"matcher_status":"tagged"'; then
  pass
else
  fail "case 9 no jq" "rc=$RC stdout='$STDOUT' telem='$TELEM_LINES'"
fi
rm -rf "$TMP_HOME" "$SHIM_DIR" "$out_f" "$err_f"

# --- Case 10: both jq and python3 missing → fail-soft exit 0 ------------
TMP_HOME="$(mktemp -d)"
out_f="$(mktemp)"
err_f="$(mktemp)"
SHIM_DIR="$(mktemp -d)"
for d in /usr/bin /bin; do
  [ -d "$d" ] || continue
  for src in "$d"/*; do
    [ -e "$src" ] || continue
    base="$(basename "$src")"
    case "$base" in jq|python3|python) continue ;; esac
    [ -e "$SHIM_DIR/$base" ] && continue
    ln -s "$src" "$SHIM_DIR/$base" 2>/dev/null || true
  done
done
printf '%s' '{"tool_name":"mcp__zendesk__list_tickets","tool_input":{},"session_id":"s10"}' \
  | HOME="$TMP_HOME" PATH="$SHIM_DIR" bash "$HOOK" >"$out_f" 2>"$err_f"
RC=$?
if [ "$RC" -eq 0 ]; then
  pass
else
  fail "case 10 fail-soft" "rc=$RC stderr=$(cat "$err_f")"
fi
rm -rf "$TMP_HOME" "$SHIM_DIR" "$out_f" "$err_f"

printf 'test-wrap-mcp-output: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
