# `eval-contamination-probe` — gold-patch-by-ID detector

v2.0 P1 #5. Charter §7 SLO list +1 line.

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body. |
| `CLAUDE.md` | Skill-author guidance for adding the probe. |
| `templates/probe-test.yaml` | Promptfoo case template — copy and fill in. |
| `templates/probe-id-format.md` | Probe ID format reference. |
| `tests/test-probe-detect.sh` | Self-test on contaminated/clean fixtures. |
| `examples/contaminated-fixture.yaml` | Deliberately contaminated eval (should FAIL). |
| `examples/clean-fixture.yaml` | Clean eval (should PASS). |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |

## Why probe-by-ID over generic detectors

A generic "did the model output match the reference solution literally?" check has a 1–2% false-positive rate on simple solutions (the model converges on the same answer). The probe-by-ID approach uses a salted unique string (`PROBE-<sha8>-<feature>-<idx>_REFERENCE_SOLUTION:`) that **cannot** land naturally — its presence in output is unambiguous evidence of contamination.

## Install


## Self-test

```bash
bash core/eval-contamination-probe/tests/test-probe-detect.sh
```

Expected output:

- `examples/contaminated-fixture.yaml` → probe FAILS (= contamination caught).
- `examples/clean-fixture.yaml` → probe PASSES (= no false positive).

If Promptfoo is not installed locally, the self-test falls back to a synthetic substring check against the fixture files.

## References

- Charter §7: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
