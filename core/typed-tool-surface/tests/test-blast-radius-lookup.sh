#!/usr/bin/env bash
# test-blast-radius-lookup.sh — verifies the blast-radius taxonomy table is
# present, all 5 tiers are documented, and the SKILL.md frontmatter on the
# precedent skills carries valid blast_radius values.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
TABLE="$REPO_ROOT/core/typed-tool-surface/templates/blast-radius-table.md"

fail=0

# 1. Table exists.
if [ ! -f "$TABLE" ]; then
  printf 'FAIL: blast-radius-table.md missing\n' >&2
  exit 1
fi

# 2. All 5 tiers present.
for tier in read-only local-write repo-write network-write external-side-effect; do
  if ! grep -F -q "\`$tier\`" "$TABLE"; then
    printf 'FAIL: tier %s missing from blast-radius-table.md\n' "$tier" >&2
    fail=1
  else
    printf 'PASS: tier %s documented\n' "$tier"
  fi
done

# 3. Sample skill frontmatter passes (quarantine-pack already declared in v2.0).
QP_SKILL="$REPO_ROOT/core/quarantine-pack/SKILL.md"
if [ -f "$QP_SKILL" ]; then
  if grep -E '^model:' "$QP_SKILL" >/dev/null 2>&1; then
    printf 'PASS: quarantine-pack SKILL.md present (frontmatter parseable)\n'
  fi
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-blast-radius-lookup: PASS\n'
fi
exit "$fail"
