# Example 03 — `feature`: new API endpoint with tests

## Input

```yaml
prompt: |
  implement /api/v2/users endpoint with full CRUD
  - routes/users.ts
  - controllers/users.ts
  - services/users.ts
  - tests/users.test.ts
files_in_scope:
  - "src/routes/users.ts"
  - "src/controllers/users.ts"
  - "src/services/users.ts"
  - "tests/users.test.ts"
tool_plan: ["Read", "Edit", "Write", "Bash"]
loc_hint: 220
```

## Reasoning trace

- **Rung 1 (path)**: no audit path → skip
- **Rung 2 (keyword)**: `implement` matches `feature_kw` → floor = `feature`, `signals_used = ["keyword"]`
- **Rung 3 (file-count)**: 4 files in [2..5] → floor = max(feature, feature) = `feature`, `signals_used += ["file-count"]`
- **Rung 4 (LOC)**: 220 LOC ≥ 150 → reinforces `feature`, `signals_used += ["loc"]`
- **Rung 5 (tool-plan)**: Edit/Write/Bash → no further upgrade (above small)
- **Rung 6 (reasoning-depth)**: ~5-6 steps (design route, write controller, wire service, write tests, run tests, lint) → small floor → no upgrade

No tie-break.

## Output

```json
{
  "class": "feature",
  "rationale": "implement keyword + 4 files + 220 LOC delta",
  "signals_used": ["keyword", "file-count", "loc"],
  "files_in_scope": 4,
  "loc_estimate": 220,
  "tie_break_applied": false
}
```

## Downstream

`model-router` maps `feature` → `claude-sonnet-4-6`. No fences fire. Final: Sonnet 4.6.

## Counter-factual: 7 files

If the file list grew to 7 (add validators, models, OpenAPI), Rung 3 forces `system` → Opus 4.7. R1 §4 row 5: Sonnet adequate for ≤5 files; >5 files calls for Opus.
