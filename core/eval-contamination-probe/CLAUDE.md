# eval-contamination-probe — skill-author guidance

When you author a new Promptfoo `tasks.yaml`:

1. Generate a probe ID per case: `PROBE-$(echo -n "${FEATURE}-${IDX}" | sha256sum | cut -c1-8)-${FEATURE}-${IDX}`.
2. In each case, set `vars.probe_id: "<id>"`.
3. Add an assertion: `- type: not-contains` `value: "{{probe_id}}_REFERENCE_SOLUTION:"`.
4. Run the contamination self-test: `bash core/eval-contamination-probe/tests/test-probe-detect.sh`.

The probe ID literal must NEVER appear in:

- The eval prompt itself (it would tip off the model — the salted ID is for assertion, not for the prompt).
- The reference solution (which lives in `decisions.md` or the spec doc, not in the eval input).

If the eval output ever contains the literal `<probe_id>_REFERENCE_SOLUTION:`, that is direct evidence the input was contaminated upstream.

## Why this lives in CLAUDE.md, not just the templates dir

Skill authors are agents too. The fragment is here so that when Claude is asked to write a new `tasks.yaml`, the prompt-time agent has the guidance inline.

End of `core/eval-contamination-probe/CLAUDE.md`.
