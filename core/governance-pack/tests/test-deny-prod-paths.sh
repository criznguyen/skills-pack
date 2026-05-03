#!/usr/bin/env bash
# test-deny-prod-paths.sh — unit tests for governance-pack/hooks/deny-prod-paths.sh
#
# v1.4.3 introduces a per-project allowlist mechanism: a project containing
# `.claude/governance-allow.txt` may list glob patterns that win over the
# universal denylist (audit-mode workflows).
#
# 4 cases per v1.4.3 spec + 1 v1.4.4 hardening case:
#   A1 deny-only match     — no allow-file; denylist hit → exit 2
#   A2 allow-only match    — allow-file matches; denylist would NOT match anyway → exit 0 + JSONL
#   A3 both match (allow-wins) — allow-file AND denylist match → exit 0 + JSONL
#   A4 neither match       — exit 0 + no JSONL
#   A5 broken-jq fallback  — broken `jq` shim in PATH; hook must fall through to
#                            python3/grep and STILL block the path (no silent bypass)
#
# Each case runs in an isolated mktemp -d project with .git/ and per-test
# allow/deny files. trap cleanup ensures no real state is touched.
#
# Usage: bash core/governance-pack/tests/test-deny-prod-paths.sh
# Exit 0 = all PASS; exit 1 = any FAIL.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/deny-prod-paths.sh"

[ -x "$HOOK" ] || { echo "FAIL: hook not executable at $HOOK" >&2; exit 1; }

PASS=0
FAIL=0
RESULTS=()

# Make a sandbox project rooted at $TMP/proj with .git/, optional governance-allow,
# and a denylist patterns file. Returns the project root.
mkproject() {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/proj/.git"
  mkdir -p "$d/proj/internal/auth"
  mkdir -p "$d/proj/db/migrations"
  mkdir -p "$d/proj/internal/billing"
  mkdir -p "$d/proj/.claude"
  printf '%s' "$d/proj"
}

# Build PreToolUse JSON for an Edit on a given absolute file_path.
mkjson() {
  local file="$1"
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"session_id":"test"}' "$file"
}

# Standard universal denylist for tests (the patterns ciscrm hit on).
write_deny() {
  local f="$1"
  cat > "$f" <<'DENY'
**/auth/**
**/migrations/**
**/billing/**
DENY
}

write_allow() {
  local f="$1" pattern="$2"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$pattern" > "$f"
}

record() {
  local name="$1" cond="$2" detail="$3"
  if [ "$cond" -eq 1 ]; then
    PASS=$((PASS+1))
    RESULTS+=("PASS $name")
  else
    FAIL=$((FAIL+1))
    RESULTS+=("FAIL $name: $detail")
  fi
}

# ---------- A1 — deny-only match (no allow-file) → exit 2 -----------
test_a1_deny_only() {
  local proj deny target
  proj="$(mkproject)"
  deny="$proj/.claude/prod-paths.txt"
  write_deny "$deny"
  target="$proj/internal/auth/middleware.go"
  touch "$target"

  local stderr_file
  stderr_file="$(mktemp)"
  GOVERNANCE_PACK_PROD_PATHS_FILE="$deny" \
    bash "$HOOK" <<< "$(mkjson "$target")" 2>"$stderr_file"
  local rc=$?
  local stderr
  stderr="$(cat "$stderr_file")"
  rm -f "$stderr_file"

  if [ "$rc" -eq 2 ] && printf '%s' "$stderr" | grep -q 'BLOCKED'; then
    record "A1 deny-only match" 1 ""
  else
    record "A1 deny-only match" 0 "rc=$rc stderr='$stderr'"
  fi
  rm -rf "$(dirname "$proj")"
}

# ---------- A2 — allow-only match (path NOT in denylist; allow file lists it) ---
# Verifies the allow-list short-circuits BEFORE the denylist even when the
# path wouldn't have been denied — and that JSONL is written.
test_a2_allow_only() {
  local proj deny allow audit target
  proj="$(mkproject)"
  deny="$proj/.claude/prod-paths.txt"
  allow="$proj/.claude/governance-allow.txt"
  audit="$proj/.claude/state/governance-allow.jsonl"
  write_deny "$deny"
  # Path won't match denylist (no auth/billing/migrations component)
  mkdir -p "$proj/internal/svc"
  target="$proj/internal/svc/handler.go"
  touch "$target"
  write_allow "$allow" "**/internal/svc/**"

  local stderr_file
  stderr_file="$(mktemp)"
  GOVERNANCE_PACK_PROD_PATHS_FILE="$deny" \
    bash "$HOOK" <<< "$(mkjson "$target")" 2>"$stderr_file"
  local rc=$?
  local stderr
  stderr="$(cat "$stderr_file")"
  rm -f "$stderr_file"

  local jsonl_lines=0
  [ -f "$audit" ] && jsonl_lines="$(wc -l < "$audit" | tr -d ' ')"

  if [ "$rc" -eq 0 ] && [ -z "$stderr" ] && [ "$jsonl_lines" -ge 1 ]; then
    # Verify JSONL is parseable and contains the expected fields.
    local first_line
    first_line="$(head -n1 "$audit")"
    if printf '%s' "$first_line" | grep -q '"reason":"governance-allow match"' \
       && printf '%s' "$first_line" | grep -q '"matched_pattern":"\*\*/internal/svc/\*\*"' \
       && printf '%s' "$first_line" | grep -q "\"file_path\":\"$target\""; then
      record "A2 allow-only match" 1 ""
    else
      record "A2 allow-only match" 0 "JSONL malformed: $first_line"
    fi
  else
    record "A2 allow-only match" 0 "rc=$rc stderr='$stderr' jsonl_lines=$jsonl_lines"
  fi
  rm -rf "$(dirname "$proj")"
}

# ---------- A3 — both match (allow-wins) → exit 0 + JSONL --------
test_a3_allow_wins() {
  local proj deny allow audit target
  proj="$(mkproject)"
  deny="$proj/.claude/prod-paths.txt"
  allow="$proj/.claude/governance-allow.txt"
  audit="$proj/.claude/state/governance-allow.jsonl"
  write_deny "$deny"
  target="$proj/db/migrations/0001_init.sql"
  touch "$target"
  # Both denylist (**/migrations/**) and allowlist (**/migrations/**) match.
  write_allow "$allow" "**/migrations/**"

  local stderr_file
  stderr_file="$(mktemp)"
  GOVERNANCE_PACK_PROD_PATHS_FILE="$deny" \
    bash "$HOOK" <<< "$(mkjson "$target")" 2>"$stderr_file"
  local rc=$?
  local stderr
  stderr="$(cat "$stderr_file")"
  rm -f "$stderr_file"

  local jsonl_lines=0
  [ -f "$audit" ] && jsonl_lines="$(wc -l < "$audit" | tr -d ' ')"

  if [ "$rc" -eq 0 ] && [ -z "$stderr" ] && [ "$jsonl_lines" -ge 1 ]; then
    local first_line
    first_line="$(head -n1 "$audit")"
    if printf '%s' "$first_line" | grep -q '"matched_pattern":"\*\*/migrations/\*\*"'; then
      record "A3 both match (allow wins)" 1 ""
    else
      record "A3 both match (allow wins)" 0 "JSONL pattern mismatch: $first_line"
    fi
  else
    record "A3 both match (allow wins)" 0 "rc=$rc stderr='$stderr' jsonl_lines=$jsonl_lines"
  fi
  rm -rf "$(dirname "$proj")"
}

# ---------- A4 — neither match → exit 0, no JSONL --------
test_a4_neither() {
  local proj deny allow audit target
  proj="$(mkproject)"
  deny="$proj/.claude/prod-paths.txt"
  allow="$proj/.claude/governance-allow.txt"
  audit="$proj/.claude/state/governance-allow.jsonl"
  write_deny "$deny"
  mkdir -p "$proj/cmd"
  target="$proj/cmd/server.go"
  touch "$target"
  write_allow "$allow" "**/internal/auth/**"  # doesn't match target

  local stderr_file
  stderr_file="$(mktemp)"
  GOVERNANCE_PACK_PROD_PATHS_FILE="$deny" \
    bash "$HOOK" <<< "$(mkjson "$target")" 2>"$stderr_file"
  local rc=$?
  local stderr
  stderr="$(cat "$stderr_file")"
  rm -f "$stderr_file"

  local jsonl_lines=0
  [ -f "$audit" ] && jsonl_lines="$(wc -l < "$audit" | tr -d ' ')"

  if [ "$rc" -eq 0 ] && [ -z "$stderr" ] && [ "$jsonl_lines" -eq 0 ]; then
    record "A4 neither match" 1 ""
  else
    record "A4 neither match" 0 "rc=$rc stderr='$stderr' jsonl_lines=$jsonl_lines"
  fi
  rm -rf "$(dirname "$proj")"
}

# ---------- A5 — broken-jq fallback (v1.4.4) ----------
# Install a jq shim that satisfies `command -v jq` but ALWAYS fails on
# invocation. The hook must detect this via `jq --version` probe and fall
# through to python3 (or grep) so denylist still blocks the path.
test_a5_broken_jq_fallback() {
  local proj deny target shimdir
  proj="$(mkproject)"
  deny="$proj/.claude/prod-paths.txt"
  write_deny "$deny"
  target="$proj/internal/auth/middleware.go"
  touch "$target"

  shimdir="$(mktemp -d)"
  cat > "$shimdir/jq" <<'SHIM'
#!/bin/sh
exit 1
SHIM
  chmod +x "$shimdir/jq"

  local stderr_file
  stderr_file="$(mktemp)"
  # Prepend shim PATH so the broken jq is found first; keep system PATH so
  # python3 / grep are reachable for the fallback.
  PATH="$shimdir:$PATH" \
    GOVERNANCE_PACK_PROD_PATHS_FILE="$deny" \
    bash "$HOOK" <<< "$(mkjson "$target")" 2>"$stderr_file"
  local rc=$?
  local stderr
  stderr="$(cat "$stderr_file")"
  rm -f "$stderr_file"
  rm -rf "$shimdir"

  if [ "$rc" -eq 2 ] && printf '%s' "$stderr" | grep -q 'BLOCKED'; then
    record "A5 broken-jq fallback" 1 ""
  else
    record "A5 broken-jq fallback" 0 "rc=$rc stderr='$stderr' (expected exit=2 + BLOCKED — silent bypass would have given exit=0)"
  fi
  rm -rf "$(dirname "$proj")"
}

test_a1_deny_only
test_a2_allow_only
test_a3_allow_wins
test_a4_neither
test_a5_broken_jq_fallback

echo "---"
for r in "${RESULTS[@]}"; do echo "$r"; done
echo "---"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
