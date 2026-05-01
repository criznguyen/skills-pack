# Example 04 — `system`: cross-module refactor

## Input

```yaml
prompt: |
  refactor the session-store layer across all middlewares to use
  the new Redis-backed implementation. Touches 8 files spanning
  middleware/, services/, and tests/. Concurrency-sensitive — must
  preserve atomic check-then-set semantics.
files_in_scope:
  - "src/middleware/session-cookie.ts"
  - "src/middleware/session-bearer.ts"
  - "src/middleware/csrf.ts"
  - "src/services/session-store.ts"
  - "src/services/session-redis.ts"
  - "src/lib/atomic.ts"
  - "tests/session-store.test.ts"
  - "tests/session-redis.test.ts"
tool_plan: ["Read", "Edit", "Write", "Bash"]
loc_hint: 480
```

## Reasoning trace

- **Rung 1 (path)**: no audit path → skip
- **Rung 2 (keyword)**: `refactor` and `concurrency` match `system_kw` → floor = `system`, `signals_used = ["keyword"]`
- **Rung 3 (file-count)**: 8 files > 5 → reinforces `system`, `signals_used += ["file-count"]`
- **Rung 4 (LOC)**: 480 LOC ≥ 150 (and ~500 → near system threshold) → reinforces, `signals_used += ["loc"]`
- **Rung 5 (tool-plan)**: Edit/Write/Bash → no further effect
- **Rung 6 (reasoning-depth)**: >7 steps → reinforces feature floor, no upgrade past system

## Output

```json
{
  "class": "system",
  "rationale": "refactor + concurrency keywords + 8 files + 480 LOC",
  "signals_used": ["keyword", "file-count", "loc"],
  "files_in_scope": 8,
  "loc_estimate": 480,
  "tie_break_applied": false
}
```

## Downstream

`model-router` maps `system` → `claude-opus-4-7`. The `concurrency` token is not in the model-router keyword fence list (it's a class signal, not a fence), but the class itself routes to Opus. Note: a future revision could add `concurrency` to the keyword fence — current design leaves it as a class signal only.

## Why not Sonnet

R1 §4 row 8: cross-file refactor / >5 files → Opus. Sonnet's 8pp SWE-bench Verified gap to Opus widens substantially on multi-file work, and `concurrency` failure modes are exactly where R1 §5 lists "panic-loop token waste" and "tasks not in dependency order."
