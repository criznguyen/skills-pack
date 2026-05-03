#!/usr/bin/env bash
# test-check-drift.sh — 4-case suite for installed-hook-drift reporter.
#
# Cases:
#   T-IHD-1  No drift — installed copy byte-for-byte matches canonical → no output.
#   T-IHD-2  Drift — installed copy modified → emits status="drift".
#   T-IHD-3  Orphan — installed hook with no canonical counterpart in repo → emits status="orphan".
#   T-IHD-4  Custom-orphan — installed hook under a group dir not present in repo → status="orphan".

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
HOOK="$REPO_ROOT/core/installed-hook-drift/hooks/check-drift.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a fake REPO_ROOT and HOME inside TMP.
FAKE_REPO="$TMP/repo"
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_REPO/core/group-a/hooks" \
         "$FAKE_REPO/core/group-b/hooks" \
         "$FAKE_HOME/.claude/hooks/group-a" \
         "$FAKE_HOME/.claude/hooks/group-b" \
         "$FAKE_HOME/.claude/hooks/custom-group"

# Canonical hook contents.
cat > "$FAKE_REPO/core/group-a/hooks/match.sh" <<'EOF'
#!/usr/bin/env bash
echo match
EOF

cat > "$FAKE_REPO/core/group-b/hooks/will-drift.sh" <<'EOF'
#!/usr/bin/env bash
echo original
EOF

# Installed copies.
# T-IHD-1: byte-for-byte match.
cp "$FAKE_REPO/core/group-a/hooks/match.sh" \
   "$FAKE_HOME/.claude/hooks/group-a/match.sh"

# T-IHD-2: drifted copy (different content).
cat > "$FAKE_HOME/.claude/hooks/group-b/will-drift.sh" <<'EOF'
#!/usr/bin/env bash
echo TAMPERED
EOF

# T-IHD-3: installed hook in known group with NO canonical counterpart.
cat > "$FAKE_HOME/.claude/hooks/group-a/orphan-in-group.sh" <<'EOF'
#!/usr/bin/env bash
echo "no canonical for me"
EOF

# T-IHD-4: installed hook in a group dir that doesn't exist in repo at all.
cat > "$FAKE_HOME/.claude/hooks/custom-group/my-personal.sh" <<'EOF'
#!/usr/bin/env bash
echo custom
EOF

export HOME="$FAKE_HOME"

OUT="$(bash "$HOOK" "$FAKE_REPO" 2>&1)"
EC=$?

fail=0

if [ "$EC" -ne 0 ]; then
  printf 'FAIL: reporter must exit 0 always; got %s\n' "$EC" >&2
  fail=1
fi

# Verify no false-positive on the matching hook.
if printf '%s\n' "$OUT" | grep -F "/group-a/match.sh" | grep -q '"status":"drift"'; then
  printf 'FAIL: T-IHD-1 reported drift on byte-for-byte match\n' >&2
  fail=1
else
  printf 'PASS: T-IHD-1 no-drift hook produced no drift line\n'
fi

# Verify drift detected on tampered hook.
if printf '%s\n' "$OUT" | grep -F "/group-b/will-drift.sh" | grep -q '"status":"drift"'; then
  printf 'PASS: T-IHD-2 drift detected on tampered hook\n'
else
  printf 'FAIL: T-IHD-2 expected drift line for /group-b/will-drift.sh; got=%s\n' "$OUT" >&2
  fail=1
fi

# Verify drift line includes both shas.
DRIFT_LINE="$(printf '%s\n' "$OUT" | grep -F "/group-b/will-drift.sh")"
if printf '%s' "$DRIFT_LINE" | grep -q '"installed_sha"' && \
   printf '%s' "$DRIFT_LINE" | grep -q '"canonical_sha"'; then
  printf 'PASS: T-IHD-2.shas drift line includes installed_sha + canonical_sha\n'
else
  printf 'FAIL: T-IHD-2.shas drift line missing one or both shas: %s\n' "$DRIFT_LINE" >&2
  fail=1
fi

# Verify orphan detected on installed hook with no canonical counterpart.
if printf '%s\n' "$OUT" | grep -F "/group-a/orphan-in-group.sh" | grep -q '"status":"orphan"'; then
  printf 'PASS: T-IHD-3 orphan detected on hook with no canonical\n'
else
  printf 'FAIL: T-IHD-3 expected orphan line for /group-a/orphan-in-group.sh; got=%s\n' "$OUT" >&2
  fail=1
fi

# Verify orphan detected on a group dir not present in repo.
if printf '%s\n' "$OUT" | grep -F "/custom-group/my-personal.sh" | grep -q '"status":"orphan"'; then
  printf 'PASS: T-IHD-4 orphan detected on custom-group hook\n'
else
  printf 'FAIL: T-IHD-4 expected orphan line for /custom-group/my-personal.sh; got=%s\n' "$OUT" >&2
  fail=1
fi

# Bad REPO_ROOT → should emit single error line, exit 0.
BAD_OUT="$(bash "$HOOK" "$TMP/no-such-dir" 2>&1)"
BAD_EC=$?
if [ "$BAD_EC" -eq 0 ] && printf '%s' "$BAD_OUT" | grep -q '"status":"error"'; then
  printf 'PASS: T-IHD-bad-repo emits error JSONL and exit 0\n'
else
  printf 'FAIL: T-IHD-bad-repo expected exit 0 + error JSONL; got ec=%s out=%s\n' "$BAD_EC" "$BAD_OUT" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-check-drift: PASS\n'
fi
exit "$fail"
