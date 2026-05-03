# Precedence (F21)

When two counters fire on the same call, the breaker reports the *highest-precedence* halt only. The agent sees one halt line, not five.

| Order | Counter | Why this order |
|---|---|---|
| 1 (highest) | `write_count` | Write-class runaway proof (v1.7.0+). The session is in an unbounded write loop; this is the dangerous signal the breaker was originally designed to catch. |
| 2 | `read_count` | Read-class runaway proof (v1.7.0+). Exploration has gone too wide; consolidate before continuing. Should rarely fire under default 600. |
| 3 | `iteration_count` | Global sum cap. Operator-set safety net via `LOOP_BREAKER_ITER_CEILING`. |
| 4 | `usd_spent` | Runaway-cost proof. The session may still be productive but operator-budget says stop. |
| 5 (lowest) | `hash_collisions` | Redundant-work proof. The agent is repeating itself; the operator may want to investigate before counters 1 / 2 fire. |

Implementation note: the PreToolUse hook checks counters in the order above and `exit 2` on the first hit. The halt JSONL line records the *winning* counter; the other counters' state is logged for diagnostics but does not appear in the halt event.

## v1.7.0 — why write_count outranks read_count

Anti-fantasy mandates exploration reads before writes. A read-class halt is a "consolidate your search" signal; a write-class halt is a "you are looping on actions that change the world" signal. Surfacing write-class first ensures the agent reacts to the dangerous case even if read-class also crossed (which it shouldn't under the wider 600 default ceiling).

## Bypass and precedence interaction

`LOOP_BREAKER_BYPASS_TOKEN` skips ALL counter checks for that single tool call. The bypass token does NOT reset counters; the next call resumes at the same read_count + write_count + usd_spent values. Operator must explicitly reset (`rm ~/.claude/sessions/<sid>/counters.json`) to restart from zero.

## Cross-feature precedence (PreToolUse hook stack)

This file documents *intra-feature* counter precedence (write → read → sum → usd → collisions). The orthogonal *cross-feature* precedence — i.e. how
loop-circuit-breaker's PreToolUse hook orders against the other 4 PreToolUse
hooks shipped in v2.0 (file-stat, git-push-gate, schema-validate,
credential-scan) — is documented separately at
[`docs/conventions/pretooluse-hook-precedence.md`](../../../docs/conventions/pretooluse-hook-precedence.md).
