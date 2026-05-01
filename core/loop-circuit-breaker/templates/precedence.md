# Precedence (F21)

When two counters fire on the same call, the breaker reports the *highest-precedence* halt only. The agent sees one halt line, not three.

| Order | Counter | Why this order |
|---|---|---|
| 1 (highest) | `iteration_count` | Loop-runaway proof. The session is in an unbounded loop; cost / collision are downstream symptoms. Stop the loop entirely. |
| 2 | `usd_spent` | Runaway-cost proof. The session may still be productive but operator-budget says stop. |
| 3 (lowest) | `hash_collisions` | Redundant-work proof. The agent is repeating itself; the operator may want to investigate before counters 1 / 2 fire. |

Implementation note: the PreToolUse hook checks counters in the order above and `exit 2` on the first hit. The halt JSONL line records the *winning* counter; the other counters' state is logged for diagnostics but does not appear in the halt event.

## Bypass and precedence interaction

`LOOP_BREAKER_BYPASS_TOKEN` skips ALL counter checks for that single tool call. The bypass token does NOT reset counters; the next call resumes at the same iteration_count + usd_spent values. Operator must explicitly reset (`rm ~/.claude/sessions/<sid>/counters.json`) to restart from zero.

## Cross-feature precedence (PreToolUse hook stack)

This file documents *intra-feature* counter precedence (iteration → usd →
collisions). The orthogonal *cross-feature* precedence — i.e. how
loop-circuit-breaker's PreToolUse hook orders against the other 4 PreToolUse
hooks shipped in v2.0 (file-stat, git-push-gate, schema-validate,
credential-scan) — is documented separately at
[`docs/conventions/pretooluse-hook-precedence.md`](../../../docs/conventions/pretooluse-hook-precedence.md).
