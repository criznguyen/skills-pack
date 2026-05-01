# Example 01 — `trivial`: README summary

## Input

```yaml
prompt: "summarize README.md in 5 bullets"
files_in_scope: ["README.md"]
tool_plan: ["Read"]
loc_hint: null
```

## Reasoning trace

- **Rung 1 (path)**: no SDLC audit path → skip
- **Rung 2 (keyword)**: `summarize` matches `trivial_kw` → floor = `trivial`, `signals_used = ["keyword"]`
- **Rung 3 (file-count)**: 1 file → no upgrade
- **Rung 4 (LOC)**: no hint → skip
- **Rung 5 (tool-plan)**: Read-only → reinforces `trivial` ceiling, `signals_used += ["tool-plan"]`
- **Rung 6 (reasoning-depth)**: 1 step → no upgrade

## Output

```json
{
  "class": "trivial",
  "rationale": "summarize keyword + 1 file + Read-only tool plan",
  "signals_used": ["keyword", "tool-plan"],
  "files_in_scope": 1,
  "loc_estimate": null,
  "tie_break_applied": false
}
```

## Downstream

`model-router` reads `class: "trivial"` → maps to `claude-haiku-4-5`. No fences fire. Final recommendation: Haiku.
