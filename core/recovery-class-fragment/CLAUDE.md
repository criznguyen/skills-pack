# recovery-class-fragment — classifier fragment

This file IS the recovery-classifier fragment skill authors copy into their own SKILL.md/CLAUDE.md when they want the 4-class taxonomy inline. The runtime enforcement lives in `hooks/recovery-classify.sh`; this file is documentation + copy-paste source.

## The 4-class fragment (paste into your skill prose)

When a tool call returns non-empty stderr, classify the error before deciding whether to retry, surface, fix, or escalate. The 4 classes:

1. **`transient`** → primitive `retry-with-backoff`. Triggered by rate limits, network timeouts, lock contention. Fix: wait and try again with exponential backoff (cap retries at 3 — beyond that you're paying tokens for nothing).
2. **`config-drift`** → primitive `surface-and-ask`. Triggered by missing env vars, expired tokens, stale config. Fix: do NOT auto-fix; surface the missing config to the operator and ask. Auto-rewriting an env file from inferred context is the precise b3 §I-1 (Replit panic-loop) attack surface.
3. **`logic-error`** → primitive `fix-implementation`. Triggered by `TypeError`, `AssertionError`, `NullPointerException`, contract violations. Fix: read the call site, fix the implementation, re-run. Do NOT retry without a code change — the next call will fail identically.
4. **`external-failure`** → primitive `escalate-to-human`. Triggered by upstream 5xx, hardware failure, service down. Fix: tell the operator the service is degraded and stop. Retrying a 503 storm just costs tokens.

## Why classify before recovering

ReAct precedent (b2): an agent that retries every error class with the same primitive (usually retry-with-backoff) burns tokens on logic errors that will never recover and surfaces noise on transient errors that would have self-resolved. Classification is the cheapest disambiguation; the fix-implementation vs. retry decision is the highest-leverage one.

## Forbidden in hook bodies (TM4)

The runtime enforcement at `hooks/recovery-classify.sh` MUST NOT contain LLM-spawn literals (`claude -p`, `Agent(`, `anthropic.`, `@anthropic`). Enforced by `tests/test-no-claude-spawn.sh`. The classifier is keyword matching against a TSV — the TSV is operator-editable, the regex is not LLM-driven.

## Telemetry

The hook appends one JSONL line per call with non-empty stderr to `~/.claude/telemetry.jsonl`:

```json
{"event":"recovery-class","ts":"2026-04-29T12:00:00Z","tool":"Bash","class":"transient","primitive":"retry-with-backoff","confidence":1,"latency_ms":3,"session_id":"..."}
```

Privacy invariant (mirrors quarantine-pack AC6 / telemetry.sh line 11): the JSONL never contains the stderr body, only the resolved class + primitive. Inspect with:

```bash
jq 'select(.event=="recovery-class")' ~/.claude/telemetry.jsonl | tail -50
```

End of `core/recovery-class-fragment/CLAUDE.md`.
