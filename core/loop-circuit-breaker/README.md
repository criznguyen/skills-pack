# `loop-circuit-breaker` — per-session 3-counter circuit breaker

v2.0 Top-5 #3. Charter §2.2 sub-clause #1.

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body. |
| `CLAUDE.md` | Agent-facing fragment for halt-event handling. |
| `hooks/pretooluse-count-hash.sh` | PreToolUse(`*`). Increments iteration_count, computes hash, checks collisions, refuses on threshold. |
| `hooks/posttooluse-cost.sh` | PostToolUse(`*`). Increments usd_spent based on model+token estimate. |
| `hooks/stop-summary.sh` | Stop. Prints session summary; resets counters. |
| `templates/counters-schema.json` | JSON schema for counters.json. |
| `templates/precedence.md` | F21 precedence table. |
| `tests/test-counters.sh` | iteration / cost / collision unit suite. |
| `tests/test-bypass-token.sh` | round-trip bypass-token verification. |
| `tests/test-hash-collision.sh` | dedicated hash-collision case. |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |
| `examples/halt-event.jsonl` | sample halt JSONL. |
| `examples/sample-counters.json` | mid-session sample. |

## Install / Uninstall

```bash
bash core/governance-pack/install.sh   # Step 15
bash core/governance-pack/uninstall.sh
rm -rf ~/.claude/loop-circuit-breaker ~/.claude/sessions/*/counters.json
```

## Performance budget

| Metric | Target |
|---|---|
| Median per-call latency (PreToolUse) | ≤ 5 ms |
| Hard timeout | 5000 ms |

## Acceptance — 4 Promptfoo fixtures


| Fixture | Scenario |
|---|---|
| `11a-iteration-cap.jsonl` | 200-call run halts at 150 |
| `11b-usd-ceiling.jsonl` | cost-based halt |
| `11c-hash-collision.jsonl` | 3 identical tool calls in rolling 10-call window halt |
| `11d-bypass-token.jsonl` | bypass token passes through unimpeded |

## References

- Bypass protocol: [`docs/conventions/loop-circuit-breaker-bypass.md`](../../docs/conventions/loop-circuit-breaker-bypass.md)
