---
name: loop-circuit-breaker
description: Per-session 3-counter circuit breaker — iteration count (default 150 per Fansipan F10), USD cost (model-routing CQR price table; SHA-pin per F11), and tool-call hash collisions (3 collisions in rolling 10-call window). Halts via stderr `[LOOP-CIRCUIT-BREAKER] halted ...` + JSONL telemetry. Bypass via orchestrator-issued `LOOP_BREAKER_BYPASS_TOKEN` env-var. Stop hook surfaces session summary. v2.0 Top-5 #3, charter §2.2 sub-clause.
type: governance
tools: Bash, Read, Edit, Write
model: opus
blast_radius: local-write
loop_iteration_cap: 150
last-validated: 2026-04-29
---

# loop-circuit-breaker

Charter §2.2 sub-clause #1 (added by this feature). Every autonomous loop declares a halt condition the harness can check deterministically. Three counters run per-session under `~/.claude/sessions/<session_id>/counters.json`:

1. **`iteration_count`** — incremented on every PreToolUse `*` event. Default ceiling 150 (Fansipan F10).
2. **`usd_spent`** — incremented on every PostToolUse `*` event by looking up the model price from `opinions/model-routing/cqr-locks.example.txt` (SHA-pinned per F11). Default ceiling configurable; advisory-only when missing.
3. **`hash_collisions`** — canonicalize `tool_name + sorted(tool_input keys)` → sha256; collision = same hash within rolling 10-call window. Ceiling 3.

A halt event emits stderr line `[LOOP-CIRCUIT-BREAKER] halted: counter=<X> value=<V> ceiling=<C>` + a JSONL telemetry line. The PreToolUse hook returns exit 2 to block; the orchestrator drains the halt-event from sub-agent stdout/JSONL and decides bypass-and-resume vs kill (charter §2.2 sub-clause "background-safe" requirement, F12 fix).

## When to use

Auto-installed by `core/governance-pack/install.sh` Step 15. Operators running long autonomous loops (Ralph-loop, mega-build sub-agents, batch refactor jobs) get hard ceilings without manual `kill` discipline.

## When NOT to use

- **For interactive sessions** where the operator is reviewing every tool call. The 150-iteration cap is sized for autonomous loops; interactive sessions naturally fall well below it.
- **As an over-spend prevention against bursty Bash output.** The breaker counts *tool calls*, not output bytes. If you need byte-budget enforcement, use `safe-spawn-claude.sh` (P0 opinion-pack) on the spawn side.

## Bypass — orchestrator-issued token

The breaker is designed to halt sub-agents the orchestrator drove off-script. The orchestrator drains the halt event from stderr, decides whether to resume, and on resume issues a fresh bypass token:

```bash
TOKEN="$(date +%s | sha256sum | cut -c1-16)"
echo "$TOKEN" > ~/.claude/loop-circuit-breaker/bypass-token.sha
LOOP_BREAKER_BYPASS_TOKEN="$TOKEN" /path/to/safe-spawn-claude.sh ...
```

The hook reads `~/.claude/loop-circuit-breaker/bypass-token.sha` every invocation and compares against `LOOP_BREAKER_BYPASS_TOKEN` exact. The token is single-session by convention — orchestrator writes a fresh token each spawn.

Per-session disable (`LOOP_BREAKER_DISABLE=1`) is also honored.

## Precedence (F21)

When two counters fire on the same call, precedence is:

1. `iteration_count` ceiling (highest precedence — terminates the loop entirely).
2. `usd_spent` ceiling.
3. `hash_collisions` ceiling.

Reason: iteration count is the loop-runaway proof; cost is the runaway-cost proof; hash collision is the redundant-work proof. The first two are runaway signals; the third is "you should stop and think." Documented in `templates/precedence.md`.

## Forbidden in hook bodies (TM4)

The 3 hooks (`pretooluse-count-hash.sh`, `posttooluse-cost.sh`, `stop-summary.sh`) are shell + jq + python3-fallback + sha256sum only. Enforced by `tests/test-no-claude-spawn.sh`.

## Telemetry

```json
{"event":"loop-circuit-breaker","ts":"...","counter":"iteration_count|usd_spent|hash_collisions","value":151,"ceiling":150,"action":"halt|increment|bypass","session_id":"..."}
```

Privacy invariant: only counter name + value + ceiling + action + session_id. The tool_name + canonical hash are NOT persisted (the hash is per-call, not per-session, by design).

## Install / Uninstall

Wired by `core/governance-pack/install.sh` Step 15. Three-command uninstall:

```bash
bash core/governance-pack/uninstall.sh
rm -rf ~/.claude/loop-circuit-breaker ~/.claude/sessions/*/counters.json
```

## References

- Charter §2.2 sub-clause #1: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
- Orchestrator bypass protocol: [`docs/conventions/loop-circuit-breaker-bypass.md`](../../docs/conventions/loop-circuit-breaker-bypass.md)
- Fansipan F10/F11/F21: see incident log
- Background-safe spawn precedent: [`opinions/safe-spawn-claude.sh`](../../opinions/)
