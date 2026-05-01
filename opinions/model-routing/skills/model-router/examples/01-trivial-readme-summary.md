# Example 01 — trivial summarization

## Input

```yaml
prompt: "spawn a sub-agent to read and summarize the top-level README.md"
cwd: "/home/criznguyen/projects/claude-skills"
files_in_scope: ["README.md"]
subagent_type: null
tool_plan: ["Read", "WebFetch?"]
context_utilization_pct: 4
env.CLAUDE_PIN_MODEL: unset
```

## Reasoning trace

1. **Step 1 fences**: `cwd` does not match Fansipan or sensitive paths. No keyword fence (no `audit/security/...`). No destructive shell. `subagent_type` is null. `CLAUDE_PIN_MODEL` not set. → continue.
2. **Step 2 tripwire**: `route-tripwire.json` empty. → continue.
3. **Step 3 classify**: `task-class-routing` returns `trivial` (signal: keyword `summarize` + single file, ≤50K context).
4. **Step 4 map**: `trivial` → `claude-haiku-4-5`.
5. **Step 5 escalations**: no triggers fire (1 file, 0 LOC delta, no plan mode, no research role).
6. **Step 6 BrowseComp**: model is not Opus 4.7. → skip.
7. **Step 7 confidence**: clean class-map, no triggers, single-file → `0.85`.

## Output

```json
{
  "model": "claude-haiku-4-5",
  "class": "trivial",
  "confidence": 0.85,
  "reason": "class-map",
  "escalation_triggers_seen": [],
  "fence_hit": ""
}
```

## How the caller applies it

```bash
/home/criznguyen/bin/safe-spawn-claude.sh /tmp/agent-readme-summary.md \
  claude-haiku-4-5 readme-summary
```
