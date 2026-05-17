---
name: eval-contamination-probe
description: Promptfoo case template + self-test that catches eval contamination. Each evaluation case carries a unique probe ID (`PROBE-<sha8>-<feature>-<idx>`); if the evaluation input contains the literal reference solution (`${PROBE_ID}_REFERENCE_SOLUTION:`) verbatim, the test FAILS — proof of contamination. Charter §7 SLO list +1 line. v2.0 P1 #5.
paths: ["**/tasks.yaml", "**/golden-tasks/**", "**/evals/**", "**/promptfoo*"]
when_to_use: Authoring a Promptfoo `tasks.yaml`, golden eval suite, or any automated LLM evaluation where contamination would silently false-PASS the run.
argument-hint: <eval-case-or-feature-slug>
type: governance
tools: Read, Bash
model: opus
blast_radius: read-only
last-validated: 2026-04-29
---

# eval-contamination-probe

Charter §7 names verifiability the highest-leverage governance input. The "70%-then-falls-apart" failure mode (Columbia DAPLab) is one symptom of eval contamination: the eval inputs leak the reference solution back into the prompt, the model reproduces it, and the eval reports false-PASS. The probe-by-ID pattern catches this deterministically.

## When to use

Every Promptfoo `tasks.yaml` shipped under `tests/golden-tasks/<NN>-<feature>/`. The case template includes a per-case `PROBE-<sha8>-<feature>-<idx>` ID and an `assert: not-contains` against the literal `${PROBE_ID}_REFERENCE_SOLUTION:` substring.

## When NOT to use

- **For evals where the reference solution is meant to appear in the input** (e.g., a "given this code, explain it" task). In those cases, the contamination probe is irrelevant; do not add it.
- **For human-in-the-loop manual evaluations.** The probe is for automated eval suites.

## Probe ID format

`PROBE-<sha8>-<feature>-<idx>` where:

- `sha8` = first 8 hex chars of `sha256(feature_id + idx)`.
- `feature` = lowercase feature slug (e.g. `loop-circuit-breaker`).
- `idx` = 0-indexed test number within the case.

Example: `PROBE-a4f2c1d9-loop-circuit-breaker-0`.

The literal that triggers FAILURE: `<PROBE_ID>_REFERENCE_SOLUTION:` followed by any text. Example: `PROBE-a4f2c1d9-loop-circuit-breaker-0_REFERENCE_SOLUTION: the model should halt at iteration 150.`

## How to add the probe to a tasks.yaml

```yaml
tests:
  - description: "11a-iteration-cap"
    vars:
      probe_id: "PROBE-a4f2c1d9-loop-circuit-breaker-0"
      context: |
        ... your eval input ...
    assert:
      - type: not-contains
        value: "{{probe_id}}_REFERENCE_SOLUTION:"
```

If the literal `<probe_id>_REFERENCE_SOLUTION:` appears anywhere in the eval output, Promptfoo fails the case. The **only** way for that literal to appear is if it leaked through from a contaminated input — the probe ID is salted, so it cannot land naturally.

## Self-test

`tests/test-probe-detect.sh` runs Promptfoo `validate` (or a synthetic check if Promptfoo is missing) on:

- `examples/contaminated-fixture.yaml` — deliberately contaminated; should FAIL the not-contains assertion.
- `examples/clean-fixture.yaml` — clean; should PASS.

The self-test FAILS the build if the contaminated fixture passes (= probe is broken) OR the clean fixture fails (= probe over-triggers).

## Charter §7 SLO line

Per `docs/synthesis/v1.1/charter-v1.1.md` §7 (`Eval skeleton commitment`), v2.0 adds:

> Every eval ships a contamination probe — gold-patch-by-ID test that fails when the eval input contains the reference solution verbatim.

This single line is the only charter touch for E.5.

## References

- Final report v2.0 plan: [`docs/research/harness-skills-required/00-final-report.md`](../../docs/research/harness-skills-required/00-final-report.md) §5 P1 #5
- Charter §7 SLO list: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
- Hamel Husain's binary-pass-fail discipline: <https://hamel.dev/blog/posts/field-guide/>
- Eugene Yan's anti-pattern note on generic benchmarks: <https://eugeneyan.com/writing/llm-patterns/>
