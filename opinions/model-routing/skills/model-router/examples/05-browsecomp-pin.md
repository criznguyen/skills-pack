# Example 05 — long-context browse work pins Opus 4.6 (not 4.7)

## Input

```yaml
prompt: |
  Spawn a research sub-agent to browse GitHub for the top 20 OSS
  workflow-orchestration tools, fetch their READMEs and recent
  commits, synthesize a comparison matrix, and recommend three for
  evaluation. Will need WebSearch + WebFetch heavily.
cwd: "/home/criznguyen/projects/research-spike"
files_in_scope: []
subagent_type: "Trend Researcher"
tool_plan: ["WebSearch", "WebFetch", "Read", "Write"]
context_utilization_pct: 22
estimated_context_tokens: 80000
env.CLAUDE_PIN_MODEL: unset
```

## Reasoning trace

1. **Step 1 fences**: no Fansipan, no sensitive paths, no keyword fence, no destructive shell. `subagent_type: "Trend Researcher"` is not in the role-fence list. → continue.
2. **Step 2 tripwire**: empty. → continue.
3. **Step 3 classify**: `task-class-routing` returns `system` (research synthesis, multi-source, deep reasoning chain).
4. **Step 4 map**: `system` → `claude-opus-4-7`.
5. **Step 5 escalations**: `subagent-research` fires (research role + WebFetch). Already at Opus, no further upgrade. `escalation_triggers_seen += ["subagent-research"]`.
6. **Step 6 BrowseComp**: model is `claude-opus-4-7` AND estimated context >50K AND prompt mentions `browse`/`WebSearch`/`WebFetch`/`research` AND subagent_type is research-oriented → **swap to `claude-opus-4-6`**. `escalation_triggers_seen += ["browsecomp-pin"]`. `reason = "browsecomp-pin"`.
7. **Step 7 confidence**: BrowseComp pin is well-grounded in R1 §3 (-4.4pp regression on Opus 4.7). → `0.85`.

## Output

```json
{
  "model": "claude-opus-4-6",
  "class": "system",
  "confidence": 0.85,
  "reason": "browsecomp-pin",
  "escalation_triggers_seen": ["subagent-research", "browsecomp-pin"],
  "fence_hit": "",
  "notes": "Opus 4.7 has -4.4pp BrowseComp regression vs 4.6; pinning 4.6"
}
```

## Anchor

R1 §3, §5 #11; FINAL §3 row 10. This is the only case where we route to Opus 4.6 instead of 4.7 — every other Opus path uses 4.7.

## How the caller applies it

```bash
/home/criznguyen/bin/safe-spawn-claude.sh /tmp/agent-orchestration-research.md \
  claude-opus-4-6 orchestration-research
```
