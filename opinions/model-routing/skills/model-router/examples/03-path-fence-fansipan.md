# Example 03 — Fansipan path fence (absolute Opus rule)

## Input

```yaml
prompt: "fix the typo in the welcome banner string"
cwd: "/home/criznguyen/projects/fansipan"
files_in_scope: ["src/components/WelcomeBanner.tsx"]
subagent_type: null
tool_plan: ["Read", "Edit"]
context_utilization_pct: 6
env.CLAUDE_PIN_MODEL: unset
```

## Reasoning trace

1. **Step 1 — path fence (Fansipan)**: `cwd` matches `**/projects/fansipan/**`. Fansipan absolute rule: ANY task touching this tree — even a 3-character typo fix — uses Opus. The class would otherwise be `trivial` → Haiku, but the path fence overrides everything except `CLAUDE_PIN_MODEL`.
2. **Steps 2-7 skipped** (Step 1 short-circuits).

## Output

```json
{
  "model": "claude-opus-4-7",
  "class": "unknown",
  "confidence": 1.0,
  "reason": "path-fence-fansipan",
  "escalation_triggers_seen": [],
  "fence_hit": "/home/criznguyen/projects/fansipan",
  "notes": "Fansipan absolute rule — typo fix would otherwise be trivial/Haiku"
}
```

## Why `class` is `unknown`

The fence fires before `task-class-routing` runs. We don't pay the classification cost when the answer is fixed.

## How the caller applies it

```bash
/home/criznguyen/bin/safe-spawn-claude.sh /tmp/agent-fansipan-typo.md \
  claude-opus-4-7 fansipan /home/criznguyen/projects/fansipan
```

## Anti-pattern

Do NOT downshift Fansipan tasks to save cost — even cosmetic tasks must use Opus per the FANSIPAN ABSOLUTE RULE in `~/.claude/CLAUDE.md`.
