#!/usr/bin/env bash
# test-install.sh — TMPHOME-isolated suite for coauthor-attribution-strip.
#
# Cases:
#   T-CAS-1  Fresh install — no settings.json → writes file with
#            .attribution.commit="".
#   T-CAS-2  Idempotent re-run — re-running on canonical settings.json
#            produces no duplicate entry / no spurious backup write to
#            the .attribution path.
#   T-CAS-3  Drift recovery — settings.json with a stale
#            .attribution.commit="some-old-trailer" gets rewritten to
#            canonical "".
#   T-CAS-4  Pre-existing settings preserved — .theme / .env / etc.
#            untouched on canonicalize write.
#   T-CAS-5  Opt-out via env — COAUTHOR_ATTRIBUTION_STRIP_DISABLE=1
#            short-circuits with no write.
#   T-CAS-6  --dry-run — prints plan, no write.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
INSTALL="$REPO_ROOT/core/coauthor-attribution-strip/install.sh"

if [ ! -x "$INSTALL" ]; then
  printf 'FAIL: %s not executable\n' "$INSTALL" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# Helper — run install.sh under an isolated $HOME.
run_install() {
  local home="$1"
  shift
  HOME="$home" CLAUDE_HOME="$home/.claude" "$INSTALL" "$@"
}

# Helper — read .attribution.commit from settings.json (jq required by
# the install script's prereq, so safe to require here).
read_commit() {
  jq -r '.attribution.commit // "ABSENT"' "$1" 2>/dev/null || echo PARSE_ERR
}

# --- T-CAS-1: fresh install ----------------------------------------------
H1="$TMP/case1"
mkdir -p "$H1"
if ! run_install "$H1" >/dev/null 2>&1; then
  printf 'FAIL: T-CAS-1 install exit non-zero on fresh home\n' >&2
  fail=1
fi
S1="$H1/.claude/settings.json"
if [ ! -f "$S1" ]; then
  printf 'FAIL: T-CAS-1 settings.json not created\n' >&2
  fail=1
elif [ "$(read_commit "$S1")" = "" ]; then
  printf 'PASS: T-CAS-1 fresh install writes .attribution.commit=""\n'
else
  printf 'FAIL: T-CAS-1 expected .attribution.commit="" got=%s\n' "$(read_commit "$S1")" >&2
  fail=1
fi

# --- T-CAS-2: idempotent re-run ------------------------------------------
# Run again; capture pre/post hashes — should match.
PRE_HASH="$(sha256sum "$S1" | cut -d' ' -f1)"
PRE_BAKS="$(ls -1 "$H1/.claude/" 2>/dev/null | grep -c 'settings.json.bak.coauthor' || true)"
if ! run_install "$H1" >/dev/null 2>&1; then
  printf 'FAIL: T-CAS-2 install exit non-zero on idempotent re-run\n' >&2
  fail=1
fi
POST_HASH="$(sha256sum "$S1" | cut -d' ' -f1)"
POST_BAKS="$(ls -1 "$H1/.claude/" 2>/dev/null | grep -c 'settings.json.bak.coauthor' || true)"
if [ "$PRE_HASH" = "$POST_HASH" ] && [ "$PRE_BAKS" -eq "$POST_BAKS" ]; then
  printf 'PASS: T-CAS-2 idempotent re-run: hash unchanged AND no extra backup\n'
else
  printf 'FAIL: T-CAS-2 hash or backup-count drift on re-run (pre=%s post=%s preBaks=%s postBaks=%s)\n' \
    "$PRE_HASH" "$POST_HASH" "$PRE_BAKS" "$POST_BAKS" >&2
  fail=1
fi

# --- T-CAS-3: drift recovery ----------------------------------------------
H3="$TMP/case3"
mkdir -p "$H3/.claude"
cat > "$H3/.claude/settings.json" <<'JSON'
{
  "theme": "dark",
  "attribution": {
    "commit": "Co-Authored-By: stale-trailer <stale@example.com>"
  }
}
JSON
if ! run_install "$H3" >/dev/null 2>&1; then
  printf 'FAIL: T-CAS-3 install exit non-zero on drift seed\n' >&2
  fail=1
fi
S3="$H3/.claude/settings.json"
if [ "$(read_commit "$S3")" = "" ]; then
  printf 'PASS: T-CAS-3 drift recovered: stale value rewritten to ""\n'
else
  printf 'FAIL: T-CAS-3 expected drift recovery to ""; got=%s\n' "$(read_commit "$S3")" >&2
  fail=1
fi

# Verify backup was made.
if ls -1 "$H3/.claude/" 2>/dev/null | grep -q 'settings.json.bak.coauthor'; then
  printf 'PASS: T-CAS-3.bak backup file written before drift-recovery\n'
else
  printf 'FAIL: T-CAS-3.bak no backup found in %s\n' "$H3/.claude/" >&2
  fail=1
fi

# --- T-CAS-4: pre-existing settings preserved -----------------------------
# Same case3 settings.json had .theme = "dark"; verify it survived.
THEME_AFTER="$(jq -r '.theme // "ABSENT"' "$S3" 2>/dev/null || echo PARSE_ERR)"
if [ "$THEME_AFTER" = "dark" ]; then
  printf 'PASS: T-CAS-4 pre-existing .theme preserved across drift recovery\n'
else
  printf 'FAIL: T-CAS-4 pre-existing .theme lost; got=%s\n' "$THEME_AFTER" >&2
  fail=1
fi

# --- T-CAS-5: opt-out via env --------------------------------------------
H5="$TMP/case5"
mkdir -p "$H5"
if ! HOME="$H5" CLAUDE_HOME="$H5/.claude" \
     COAUTHOR_ATTRIBUTION_STRIP_DISABLE=1 \
     "$INSTALL" >/dev/null 2>&1; then
  printf 'FAIL: T-CAS-5 install exit non-zero with opt-out env\n' >&2
  fail=1
fi
if [ ! -e "$H5/.claude/settings.json" ]; then
  printf 'PASS: T-CAS-5 opt-out env: no settings.json written\n'
else
  printf 'FAIL: T-CAS-5 settings.json was created despite opt-out\n' >&2
  fail=1
fi

# --- T-CAS-6: --dry-run ---------------------------------------------------
H6="$TMP/case6"
mkdir -p "$H6"
if ! run_install "$H6" --dry-run >/dev/null 2>&1; then
  printf 'FAIL: T-CAS-6 install exit non-zero on --dry-run\n' >&2
  fail=1
fi
if [ ! -e "$H6/.claude/settings.json" ]; then
  printf 'PASS: T-CAS-6 --dry-run: no settings.json written\n'
else
  printf 'FAIL: T-CAS-6 --dry-run wrote settings.json\n' >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-install (coauthor-attribution-strip): PASS\n'
fi
exit "$fail"
