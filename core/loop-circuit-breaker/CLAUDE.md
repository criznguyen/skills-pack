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

If the halt was on `hash_collisions`, the breaker is telling you that the same canonical tool call has fired 3 times in the last 10 calls. That is a redundant-work signal — re-read your last assistant turn, ask whether the task converges, and stop the loop yourself rather than waiting for a higher counter to fire.

End of `core/loop-circuit-breaker/CLAUDE.md`.
