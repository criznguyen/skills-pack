# loop-circuit-breaker — agent-facing fragment

When the breaker halts the session you will see a stderr line:

```
[LOOP-CIRCUIT-BREAKER] halted: counter=<X> value=<V> ceiling=<C>
```

Do NOT auto-bypass. The correct recovery sequence:

1. **Stop** the current task.
2. **Summarize** what was accomplished and what remains.
3. **Surface** the halt to the operator.
4. **Wait** for the operator to decide bypass-and-resume vs kill.

Do NOT write `LOOP_BREAKER_BYPASS_TOKEN` or modify `~/.claude/loop-circuit-breaker/bypass-token.sha` from inside the agent's own session. The bypass token is orchestrator-issued; the operator decides resume.

## Halt counter semantics (v1.7.0+)

| Counter | What it means | Default ceiling |
|---|---|---|
| `write_count` | Write-class tool calls (Edit, Write, MultiEdit, Bash, Agent, Task, WebFetch, MCP, ...) crossed the per-class cap. This is the dangerous-runaway signal — re-evaluate whether your loop converges. | 150 |
| `read_count` | Read-class tools (Read, Glob, Grep) crossed the per-class cap. You may be exploring the same tree repeatedly; consolidate via fewer Reads or use Glob/Grep with narrower patterns. | 600 |
| `iteration_count` | Global sum cap (read + write) crossed. Operator may have set `LOOP_BREAKER_ITER_CEILING` to a custom value. | dynamic (read + write + 100) |
| `usd_spent` | Cost ceiling crossed. Operator-budget signal. | 25.0 |
| `hash_collisions` | Same canonical tool call fired ≥3 times in last 10 calls. Redundant-work signal — re-read your last assistant turn, ask whether the task converges, and stop the loop yourself rather than waiting for a higher counter to fire. | 3 |

If the halt was on `write_count`, treat it as the original v1.6.0 iteration-cap halt: stop, summarize, surface. If the halt was on `read_count`, the breaker is telling you exploration has gone wide — narrow your search before continuing. If the halt was on `iteration_count`, the operator's global cap is set unusually low; surface and wait.

End of `core/loop-circuit-breaker/CLAUDE.md`.
