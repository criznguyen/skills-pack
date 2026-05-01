# Example 04 — feature class with file-count escalation

## Input

```yaml
prompt: |
  Implement /api/v2/users endpoint with full CRUD, including the new
  validation layer. Touch routes/users.ts, controllers/users.ts,
  services/users.ts, models/User.ts, validators/userSchema.ts,
  tests/users.test.ts, and update the OpenAPI spec.
cwd: "/home/criznguyen/projects/some-saas"
files_in_scope:
  - "src/routes/users.ts"
  - "src/controllers/users.ts"
  - "src/services/users.ts"
  - "src/models/User.ts"
  - "src/validators/userSchema.ts"
  - "tests/users.test.ts"
  - "openapi.yaml"
subagent_type: null
tool_plan: ["Read", "Edit", "Write", "Bash(npm test)"]
context_utilization_pct: 18
env.CLAUDE_PIN_MODEL: unset
```

## Reasoning trace

1. **Step 1 fences**: no Fansipan, no sensitive paths, no keyword fence (`endpoint`/`crud`/`validation` are not in the fence list), no destructive shell, no role fence. → continue.
2. **Step 2 tripwire**: empty. → continue.
3. **Step 3 classify**: `task-class-routing` returns `feature` (signal: keyword `implement` + 7 files in scope, ≤500 LOC implied). 7 files would push to `system` per signal-ladder rule 3 (>5 distinct files → system) — let's check.

   Re-evaluating: signal-ladder rule "files_in_scope > 5 → at least system". So `task-class-routing` returns `system`.
4. **Step 4 map**: `system` → `claude-opus-4-7`.
5. **Step 5 escalations**: `file-count` trigger fires (already at Opus, no further upgrade). `escalation_triggers_seen += ["file-count"]`.
6. **Step 6 BrowseComp**: model is Opus 4.7, no browse keywords. → skip.
7. **Step 7 confidence**: clean class-map at system tier with file-count escalation already at Opus → `0.85`.

## Output

```json
{
  "model": "claude-opus-4-7",
  "class": "system",
  "confidence": 0.85,
  "reason": "class-map",
  "escalation_triggers_seen": ["file-count"],
  "fence_hit": ""
}
```

## Counter-factual: 4-file version

If `files_in_scope.length == 4` (drop the schema, validator, and openapi entries; keep route/controller/service/test), the class would be `feature` → `claude-sonnet-4-6`. That's the canonical "feature on Sonnet" outcome — Sonnet 4.6 is `safe-with-caveats` for ≤5 files per R1 §4.

## How the caller applies it

```bash
/home/criznguyen/bin/safe-spawn-claude.sh /tmp/agent-users-v2-endpoint.md \
  claude-opus-4-7 users-v2
```
