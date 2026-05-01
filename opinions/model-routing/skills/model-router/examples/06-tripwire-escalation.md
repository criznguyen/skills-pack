# Example 06 — tripwire escalation (Sonnet failed, retry on Opus)

## Input

```yaml
prompt: "retry the auth refactor sub-agent — last run produced an empty stub"
cwd: "/home/criznguyen/projects/some-saas"
files_in_scope: ["src/lib/sessions.ts"]
subagent_type: null
tool_plan: ["Read", "Edit", "Bash(npm test)"]
context_utilization_pct: 14
env.CLAUDE_PIN_MODEL: unset
state_files:
  route-tripwire.json:
    - { session: "abc-123", tool: "Edit", ts: <14 minutes ago> }
    - { session: "abc-123", tool: "Bash", ts: <8 minutes ago> }
```

## Reasoning trace

1. **Step 1 fences**: would the path `src/lib/sessions.ts` match `**/auth/**`? No — it's under `lib/`, not `auth/`. But the prompt contains `auth` as a substring of "auth refactor". Whole-word match for `auth`? Not on the keyword list — the fence checks `audit | security | production | ...`. No keyword match. → continue.
   - However, if the file path had been `src/auth/sessions.ts`, the path-fence-sensitive would fire and we'd stop here.
2. **Step 2 tripwire**: 2 entries within last 30 min for current session. → `claude-opus-4-7`, confidence `0.9`, reason `tripwire-2fail`.
3. **Steps 3-7 skipped**.

## Output

```json
{
  "model": "claude-opus-4-7",
  "class": "unknown",
  "confidence": 0.9,
  "reason": "tripwire-2fail",
  "escalation_triggers_seen": ["tripwire-2fail"],
  "fence_hit": "",
  "notes": "2 failures in last 30min — escalating per trust ratchet"
}
```

## Why this matters

R1 §7 trigger #1: "First-attempt test failure on Sonnet output" has reliability **HIGH**. Two failures in 30 minutes is a strong signal that the cheaper model is mismatched to the task. Re-prompting cost negates the 3× pricing advantage.

## SessionStart hook hygiene

`session-init.sh` prunes tripwire entries older than 30 minutes on every SessionStart, so today's bans don't leak into tomorrow's session.

## How the caller applies it

```bash
/home/criznguyen/bin/safe-spawn-claude.sh /tmp/agent-auth-refactor-retry.md \
  claude-opus-4-7 auth-refactor-retry
```
