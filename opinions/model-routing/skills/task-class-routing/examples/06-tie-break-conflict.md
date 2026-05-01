# Example 06 — tie-break: trivial keyword vs. high file count

## Input

```yaml
prompt: "show me which files import the deprecated getCwd helper"
files_in_scope:
  - "src/utils/path.ts"
  - "src/utils/cwd.ts"
  - "src/lib/spawn.ts"
  - "src/lib/worktree.ts"
  - "src/cmd/build.ts"
  - "src/cmd/serve.ts"
  - "tests/utils.test.ts"
tool_plan: ["Grep", "Read"]
loc_hint: null
```

## Reasoning trace

- **Rung 1 (path)**: no audit path → skip
- **Rung 2 (keyword)**: `show` matches `trivial_kw` → floor = `trivial`, `signals_used = ["keyword"]`
- **Rung 3 (file-count)**: 7 files > 5 → would set floor = `system`. **Conflict** with trivial.
  - Tie-break rule: take higher tier → floor = `system`, set `tie_break_applied = true`, `signals_used += ["file-count"]`
- **Rung 4 (LOC)**: no hint → skip
- **Rung 5 (tool-plan)**: Read+Grep only → would cap at trivial, but tie-break already locked system. The ladder is monotonically non-decreasing once a higher tier wins; tool-plan rung adds `signals_used += ["tool-plan"]` without lowering.
- **Rung 6 (reasoning-depth)**: 1 step (grep + present) → no upgrade

## Output

```json
{
  "class": "system",
  "rationale": "trivial keyword conflicted with 7-file scope; tie-break to system",
  "signals_used": ["keyword", "file-count", "tool-plan"],
  "files_in_scope": 7,
  "loc_estimate": null,
  "tie_break_applied": true
}
```

## Why this is correct

A `Grep` across 7 files is read-only — the *task* is trivial in tool-plan terms. But the *output* is a cross-file consistency claim, which is exactly the failure mode R1 §4 row 8 calls out: "cross-file consistency analysis — Haiku escalate, Sonnet degrades on >10 files."

The conservative choice is to escalate. If the user disagrees, they can override per-spawn with `--model claude-haiku-4-5`.

## Downstream

`model-router` maps `system` → `claude-opus-4-7`. Final: Opus 4.7.

## Counter-factual: 3 files instead of 7

Same prompt with `files_in_scope.length == 3` → file-count rung sets floor = `feature`, still conflicts with `trivial` → tie-break to `feature` → Sonnet 4.6.
