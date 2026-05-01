#!/usr/bin/env bash
# test-probe-detect.sh — self-test that the contamination probe works.
#
# The contaminated fixture MUST contain the literal "<probe_id>_REFERENCE_SOLUTION:"
# in its prompt body. The clean fixture MUST NOT.
#
# Without Promptfoo we run the equivalent substring check directly: the probe
# assertion is `not-contains "{{probe_id}}_REFERENCE_SOLUTION:"` against the
# rendered prompt; the prompt body in `contaminated-fixture.yaml` includes that
# literal verbatim, so the assertion would fail (= contamination caught).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
CONTAM="$REPO_ROOT/core/eval-contamination-probe/examples/contaminated-fixture.yaml"
CLEAN="$REPO_ROOT/core/eval-contamination-probe/examples/clean-fixture.yaml"

fail=0

# Verify the contaminated fixture contains the probe_id_REFERENCE_SOLUTION: substring
# under the prompts: section, AND the probe_id in its vars.
PROBE_ID_CONTAM="$(grep -m1 -E 'probe_id:\s*"PROBE-' "$CONTAM" | sed -E 's/.*"(PROBE-[^"]+)".*/\1/')"
if [ -z "$PROBE_ID_CONTAM" ]; then
  printf 'FAIL: contaminated fixture missing probe_id var\n' >&2
  fail=1
fi

# Look for the literal "<probe_id>_REFERENCE_SOLUTION:" substring in the file.
if [ -n "${PROBE_ID_CONTAM:-}" ]; then
  if grep -F "${PROBE_ID_CONTAM}_REFERENCE_SOLUTION:" "$CONTAM" >/dev/null 2>&1; then
    printf 'PASS: contaminated fixture carries leak literal — probe would FAIL the case (= contamination caught)\n'
  else
    printf 'FAIL: contaminated fixture does NOT carry the leak literal — probe is broken\n' >&2
    fail=1
  fi
fi

# Verify the clean fixture has its probe_id but does NOT contain the leak literal.
PROBE_ID_CLEAN="$(grep -m1 -E 'probe_id:\s*"PROBE-' "$CLEAN" | sed -E 's/.*"(PROBE-[^"]+)".*/\1/')"
if [ -z "$PROBE_ID_CLEAN" ]; then
  printf 'FAIL: clean fixture missing probe_id var\n' >&2
  fail=1
fi
if [ -n "${PROBE_ID_CLEAN:-}" ]; then
  if grep -F "${PROBE_ID_CLEAN}_REFERENCE_SOLUTION:" "$CLEAN" >/dev/null 2>&1; then
    printf 'FAIL: clean fixture contains leak literal — fixture should be clean\n' >&2
    fail=1
  else
    printf 'PASS: clean fixture has no leak literal — probe would PASS the case\n'
  fi
fi

# Optional: if Promptfoo is available locally, validate the templates parse.
if command -v npx >/dev/null 2>&1 && npx -y promptfoo@0.121.9 --version >/dev/null 2>&1; then
  for f in "$CONTAM" "$CLEAN" "$REPO_ROOT/core/eval-contamination-probe/templates/probe-test.yaml"; do
    if ! npx -y promptfoo@0.121.9 validate -c "$f" >/dev/null 2>&1; then
      printf 'WARN: promptfoo validate failed on %s (template still YAML-parses; non-fatal)\n' "$f" >&2
    fi
  done
fi

if [ "$fail" -eq 0 ]; then
  printf 'test-probe-detect: PASS (contamination caught; clean is clean)\n'
fi
exit "$fail"
