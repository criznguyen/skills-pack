# `loop-circuit-breaker` — per-session circuit breaker (v1.7.0 dual counter)

v2.0 Top-5 #3. Charter §2.2 sub-clause #1.

v1.7.0: per-tool-class counter splits the original single iteration counter into `read_count` (Read/Glob/Grep, default 600) and `write_count` (every other tool, default 150). `iteration_count` is preserved as the sum for backward compat. Source: `insight_loop_circuit_breaker_v2_cap_too_tight.md`.

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body. |
| `CLAUDE.md` | Agent-facing fragment for halt-event handling. |
| `hooks/pretooluse-count-hash.sh` | PreToolUse(`*`). Increments read_count or write_count by tool class, checks per-class + sum + collision ceilings, refuses on threshold. |
| `hooks/posttooluse-cost.sh` | PostToolUse(`*`). Increments usd_spent based on model+token estimate. |
| `hooks/stop-summary.sh` | Stop. Prints session summary; resets counters. |
| `templates/counters-schema.json` | JSON schema for counters.json (read_count + write_count + iteration_count + ceilings). |
| `templates/precedence.md` | F21 precedence table. |
| `tests/test-counters.sh` | iteration / cost / collision unit suite. |
| `tests/test-tool-class-counters.sh` | v1.7.0 dedicated dual-counter suite (read-only/write-only/mixed/global-cap). |
| `tests/test-bypass-token.sh` | round-trip bypass-token verification. |
| `tests/test-hash-collision.sh` | dedicated hash-collision case. |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |
| `examples/halt-event.jsonl` | sample halt JSONL. |
| `examples/sample-counters.json` | mid-session sample. |

## Environment variables (v1.7.0)

| Var | Default | Purpose |
|---|---|---|
| `LOOP_BREAKER_READ_CEILING` | 600 | Cap on read-class counter (Read/Glob/Grep). |
| `LOOP_BREAKER_WRITE_CEILING` | 150 | Cap on write-class counter (every other tool). |
| `LOOP_BREAKER_ITER_CEILING` | `read_ceiling + write_ceiling + 100` | Global cap on `read_count + write_count`. Existing operator overrides apply unchanged. |
| `LOOP_BREAKER_USD_CEILING` | 25.0 | Cost ceiling. |

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

Located under `tests/golden-tasks/11-loop-circuit-breaker/`:

| Fixture | Scenario |
|---|---|
| `11a-iteration-cap.jsonl` | 200-call run halts at 150 |
| `11b-usd-ceiling.jsonl` | cost-based halt |
| `11c-hash-collision.jsonl` | 3 identical tool calls in rolling 10-call window halt |
| `11d-bypass-token.jsonl` | bypass token passes through unimpeded |

## References

- Final report: [`docs/research/harness-skills-required/00-final-report.md`](../../docs/research/harness-skills-required/00-final-report.md) §4 Top-5 #3
- Bypass protocol: [`docs/conventions/loop-circuit-breaker-bypass.md`](../../docs/conventions/loop-circuit-breaker-bypass.md)
