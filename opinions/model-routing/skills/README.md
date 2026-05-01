# Model Routing Skills

Two companion skills that give Claude Code a deterministic, observable model-selection layer.

| Skill | Job | Auto-invokes on |
|-------|-----|-----------------|
| [`task-class-routing/`](./task-class-routing/) | Classify a Claude Code task into one of `trivial / small / feature / system / audit` using a signal ladder over the prompt, files, and tool plan. | "what class is this task", "what tier", before any non-trivial sub-agent spawn, or whenever `model-router` calls it. |
| [`model-router/`](./model-router/) | Given a task context, return a structured JSON recommendation: `{model, class, confidence, reason, escalation_triggers_seen, fence_hit}`. | "spawn a sub-agent", "delegate", "which model", drafting `claude -p ... --model`, choosing a `subagent_type` for the Agent tool. |

Both skills emit JSON only — they never edit code, never spawn sub-agents, never call `/model`. The caller applies the recommendation.

## How they compose

```
prompt + cwd + files_in_scope + tool_plan
              │
              ▼
   ┌──────────────────────┐
   │  model-router        │   ← user-facing skill, auto-invokes on routing prompts
   │                      │
   │  Step 1: hard fences │  ── Fansipan / sensitive paths / keyword / role / destructive / session-pin → return Opus 4.7 (or pinned)
   │  Step 2: tripwire    │  ── ≥2 failures in 30min → return Opus 4.7
   │  Step 3: classify ───┼──► task-class-routing
   │  Step 4: class→model │
   │  Step 5: escalations │  ── diff-size, file-count, plan-mode, etc.
   │  Step 6: BrowseComp  │  ── browse-heavy long-context → Opus 4.6 (not 4.7)
   │  Step 7: emit JSON   │
   └──────────────────────┘
              │
              ▼
   { model, class, confidence, reason, ... }
```

`task-class-routing` is also useful standalone — e.g. a slash command that just labels the active task without picking a model.

## Decision priority (read this first)

The system has **seven** override layers. Earlier layers win against later ones, with no exceptions.

1. **`CLAUDE_PIN_MODEL` env var** — kill switch. If set, that model wins. Use this to disable downshifts wholesale (e.g., during Fansipan weeks, audit deadlines, demos).
2. **`~/.claude/state/lock-opus.flag`** — set by the `lock-opus.sh` PreToolUse hook on sensitive paths or destructive commands.
4. **Keyword fence** — `audit`, `security`, `production`, `threat model`, `refactor architecture`, `incident`, `compliance`, `migration`, `pen test`, `pentest`, `cve`.
5. **Destructive shell fence** — `rm -rf`, `git push --force`, `git reset --hard`, `DROP TABLE`, `TRUNCATE`.
6. **Sub-agent role fence** — `Security Engineer`, `Compliance Auditor`, `Blockchain Security Auditor`, `Threat Detection Engineer`, `Incident Response Commander`, `Code Reviewer` (when scope >5 files).
7. **Tripwire** — `≥2` failures in 30 min → Opus 4.7.

After all locks pass, the `class → model` mapping applies, then escalation triggers may upgrade one tier each, and finally the BrowseComp pin may swap Opus 4.7 → Opus 4.6.

## Class → model canonical table

| Class | Recommended model | Anchor |
|-------|-------------------|--------|
| `trivial` | `claude-haiku-4-5` | R1 §4 rows 1-2, 4 |
| `small` | `claude-sonnet-4-6` | R1 §4 row 5 |
| `feature` | `claude-sonnet-4-6` | R1 §4 row 5 (≤5 files); FINAL §3 row 7 |
| `system` | `claude-opus-4-7` | R1 §4 row 8; FINAL §3 row 8 |
| `audit` | `claude-opus-4-7` (LOCKED) | R1 §3 SWE-bench Pro 20pp gap; FINAL §3 row 11 |

## Outputs

### `task-class-routing` (see [`schemas/classification.json`](./task-class-routing/schemas/classification.json))

```json
{
  "class": "trivial|small|feature|system|audit",
  "rationale": "<≤140 chars>",
  "signals_used": ["path","keyword","file-count","loc","tool-plan","reasoning-depth"],
  "files_in_scope": 0,
  "loc_estimate": null,
  "tie_break_applied": false
}
```

### `model-router` (see [`schemas/recommendation.json`](./model-router/schemas/recommendation.json))

```json
{
  "model": "claude-opus-4-7|claude-opus-4-6|claude-sonnet-4-6|claude-haiku-4-5",
  "class": "trivial|small|feature|system|audit|unknown",
  "confidence": 0.0-1.0,
  "reason": "session-pin|...|browsecomp-pin",
  "escalation_triggers_seen": [...],
  "fence_hit": "<token-or-path-or-empty>"
}
```

## When each auto-invokes

`task-class-routing` should auto-invoke when:
- The agent or another skill explicitly asks "what class is this task" / "what tier" / "classify this".
- `model-router` is running and reaches Step 3.
- The user types `/task-class` or similar.

`model-router` should auto-invoke when:
- The agent is about to spawn a sub-agent (`Agent` tool, `safe-spawn-claude.sh`, `claude -p ... --model`).
- The user asks "which model should I use", "spawn a sub-agent", "delegate this", "downshift", "use cheaper", "save cost".
- Choosing a `subagent_type` value where model selection matters.

Both should NOT invoke for ordinary inline edits or reads — those follow the CLAUDE.md `## Model Routing` rubric directly.

## How callers apply a recommendation

```bash
# Bash sub-agent spawn — direct
/home/criznguyen/bin/safe-spawn-claude.sh /tmp/agent-foo.md \
  claude-haiku-4-5 trivial-fix
```

```python
# Agent tool call — Claude Code maps "haiku"/"sonnet"/"opus" to 4.5/4.6/4.7
Agent({
  description: "Summarize README",
  subagent_type: "general-purpose",
  model: "haiku"
})
```

`/model` slash: print the recommendation as a shell suggestion; never auto-run.

## Confidence interpretation

| Range | Meaning | Caller behavior |
|-------|---------|-----------------|
| `≥ 0.9` | Fence/role/destructive lock — deterministic | Apply unconditionally. |
| `0.7–0.9` | Class-map + escalation triggers | Apply; brief log line. |
| `0.55–0.7` | Class-map with low-tier output | Apply; user can override. |
| `< 0.55` | Ambiguous | Ask user before downshifting. |

## Tests

Both skills ship with Promptfoo regression suites:

- `model-router/tests/tasks.yaml` — 8 routing scenarios covering trivial/Haiku, Fansipan path fence, audit keyword fence, sensitive-path fence, file-count escalation, BrowseComp pin, tripwire-2fail, session-pin override.
- `task-class-routing/tests/tasks.yaml` — 10 classification scenarios covering all 5 classes, LOC-driven upgrade, file-count-driven escalation, audit-via-path, audit-via-keyword, and tie-break.

Run:

```bash
cd model-router && promptfoo eval -c tests/tasks.yaml
cd ../task-class-routing && promptfoo eval -c tests/tasks.yaml
```

Both grader providers are pinned to `claude-haiku-4-5` — routing decisions are cheap classification.

## Sources

- `~/.claude/CLAUDE.md` (FANSIPAN ABSOLUTE RULE, SDLC Agent Routing)

## Hard constraints (codified in both skills)

1. JSON output only — no prose narration outside the structured fields.
2. Never recommend a model not in the approved list. Opus 4.5 only on explicit user override.
3. Never recommend Haiku for code-writing work unless single-file ≤50 LOC.
4. Hard fences are not negotiable — even with high confidence in a "small" classification, a Fansipan path or `audit` keyword wins.
5. The skills observe; callers apply. No skill ever calls `/model`, `--model`, or modifies session state directly.
