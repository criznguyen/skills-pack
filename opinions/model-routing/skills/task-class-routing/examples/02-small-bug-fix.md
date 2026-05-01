# Example 02 — `small`: single-file bug fix

## Input

```yaml
prompt: "fix the off-by-one bug in pagination.ts where lastPage is wrong by 1 when total is exactly divisible by pageSize"
files_in_scope: ["src/lib/pagination.ts"]
tool_plan: ["Read", "Edit", "Bash"]
loc_hint: 8
```

## Reasoning trace

- **Rung 1 (path)**: no audit path → skip
- **Rung 2 (keyword)**: `fix` and `bug` match `small_kw` → floor = `small`, `signals_used = ["keyword"]`
- **Rung 3 (file-count)**: 1 file → no upgrade
- **Rung 4 (LOC)**: 8 LOC < 50 → no upgrade, but `signals_used += ["loc"]` (estimate was used to confirm small)
- **Rung 5 (tool-plan)**: Edit+Bash → reinforces small floor (already at small)
- **Rung 6 (reasoning-depth)**: 2-3 steps (read, edit, run test) → no upgrade

## Output

```json
{
  "class": "small",
  "rationale": "fix/bug keyword + 1 file + ~8 LOC delta",
  "signals_used": ["keyword", "loc", "tool-plan"],
  "files_in_scope": 1,
  "loc_estimate": 8,
  "tie_break_applied": false
}
```

## Downstream

`model-router` maps `small` → `claude-sonnet-4-6`. No fences. Final: Sonnet 4.6.
