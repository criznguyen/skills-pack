---
name: loop-circuit-breaker
description: Per-session circuit breaker. v1.7.0 splits the iteration counter into read-class (Read/Glob/Grep — default ceiling 600) and write-class (every other tool — default ceiling 150) to stop saturating on legitimate exploration work; cost (USD via CQR price table; SHA-pinned per F11) and tool-call hash collisions (3 in rolling 10-call window) keep the original semantics. Halts via stderr `[LOOP-CIRCUIT-BREAKER] halted ...` + JSONL telemetry. Bypass via orchestrator-issued `LOOP_BREAKER_BYPASS_TOKEN` env-var. v2.0 Top-5 #3, charter §2.2 sub-clause.
paths: []
when_to_use: Background PreToolUse counter — fires automatically per tool call to halt runaway loops; never invoked directly by the user.
disable-model-invocation: true
type: governance
tools: Bash, Read, Edit, Write
model: opus
blast_radius: local-write
loop_iteration_cap: 150
last-validated: 2026-05-04
---

# loop-circuit-breaker

Charter §2.2 sub-clause #1 (added by this feature). Every autonomous loop declares a halt condition the harness can check deterministically. Counters run per-session under `~/.claude/sessions/<session_id>/counters.json`:

1. **`read_count`** (v1.7.0+) — incremented on every PreToolUse `*` event whose `tool_name` is `Read`, `Glob`, or `Grep`. Default ceiling 600 (`LOOP_BREAKER_READ_CEILING`). Anti-fantasy mandates exploratory reads before edits — those reads are not runaway.
2. **`write_count`** (v1.7.0+) — incremented on every PreToolUse `*` event for any non-read tool (`Edit`, `Write`, `MultiEdit`, `Bash`, `Agent`, `Task`, `WebFetch`, `WebSearch`, MCP, etc.). Default ceiling 150 (`LOOP_BREAKER_WRITE_CEILING`). Write-class loops are the runaway-dangerous signal.
3. **`iteration_count`** — preserved as `read_count + write_count`. Backward-compatible global cap via `LOOP_BREAKER_ITER_CEILING` env (defaults to `read_ceiling + write_ceiling + 100` when unset). Existing operator config (e.g. `LOOP_BREAKER_ITER_CEILING=100000`) keeps working unchanged.
4. **`usd_spent`** — incremented on every PostToolUse `*` event by looking up the model price from `opinions/model-routing/cqr-locks.example.txt` (SHA-pinned per F11). Default ceiling configurable; advisory-only when missing.
5. **`hash_collisions`** — canonicalize `tool_name + sorted(tool_input keys)` → sha256; collision = same hash within rolling 10-call window. Ceiling 3.

A halt event emits stderr line `[LOOP-CIRCUIT-BREAKER] halted: counter=<X> value=<V> ceiling=<C>` + a JSONL telemetry line. The PreToolUse hook returns exit 2 to block; the orchestrator drains the halt-event from sub-agent stdout/JSONL and decides bypass-and-resume vs kill.

## Why two counters (v1.7.0)

The v1.6.0 single-counter cap of 150 saturated 4-for-4 on Wave 4.A.1 ciscrm sessions (full-stack vertical-slice sub-agents and orchestrator main sessions). Source insight: `insight_loop_circuit_breaker_v2_cap_too_tight.md`. Anti-fantasy forces ~30 exploration reads per agent before any write — combined with sqlc/test cascades and Agent spawns, the legitimate iteration count blew past 150 BEFORE the build phase finished.

Per-tool-class counter is the surgical fix: read-class halts get a 4× wider ceiling (600 default), write-class halts keep the original 150 default, and the runaway-write guard the feature was originally designed for is preserved.

## When to use

Auto-installed by `core/governance-pack/install.sh` Step 15. Operators running long autonomous loops (Ralph-loop, mega-build sub-agents, batch refactor jobs) get hard ceilings without manual `kill` discipline.

## When NOT to use

- **For interactive sessions** where the operator is reviewing every tool call. The ceilings are sized for autonomous loops; interactive sessions naturally fall well below them.
- **As an over-spend prevention against bursty Bash output.** The breaker counts *tool calls*, not output bytes. If you need byte-budget enforcement, use `safe-spawn-claude.sh` (P0 opinion-pack) on the spawn side.

## Environment variables

| Var | Default | Purpose |
|---|---|---|
| `LOOP_BREAKER_READ_CEILING` | 600 | Cap on read-class counter (Read/Glob/Grep). |
| `LOOP_BREAKER_WRITE_CEILING` | 150 | Cap on write-class counter (every other tool). |
| `LOOP_BREAKER_ITER_CEILING` | `read_ceiling + write_ceiling + 100` | Global cap on `read_count + write_count`. Existing operator overrides (e.g. `100000`) still apply. |
| `LOOP_BREAKER_USD_CEILING` | 25.0 | Cost ceiling. |
| `LOOP_BREAKER_DISABLE` | unset | `1` disables all checks for the session. |
| `LOOP_BREAKER_BYPASS_TOKEN` | unset | When matching the SHA-pin in `~/.claude/loop-circuit-breaker/bypass-token.sha`, skips checks for one tool call. |
| `LOOP_BREAKER_DIR` | `~/.claude/loop-circuit-breaker` | Override token + state directory location. |

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

1. `write_count` ceiling (highest precedence — write-class runaway is the dangerous signal).
2. `read_count` ceiling.
3. `iteration_count` ceiling (global sum cap).
4. `usd_spent` ceiling.
5. `hash_collisions` ceiling.

Reason: write-class halts surface the runaway-write loop the breaker was designed to catch; read-class halt is downstream (should rarely fire under default 600); the iteration sum is a global safety net; cost is the runaway-cost proof; hash collision is "you should stop and think." Documented in `templates/precedence.md`.

## Forbidden in hook bodies (TM4)

The 3 hooks (`pretooluse-count-hash.sh`, `posttooluse-cost.sh`, `stop-summary.sh`) are shell + jq + python3-fallback + sha256sum only. Enforced by `tests/test-no-claude-spawn.sh`.

## Telemetry

```json
{"event":"loop-circuit-breaker","ts":"...","counter":"write_count|read_count|iteration_count|usd_spent|hash_collisions","value":151,"ceiling":150,"action":"halt|increment|bypass","session_id":"..."}
```

Privacy invariant: only counter name + value + ceiling + action + session_id. The tool_name + canonical hash are NOT persisted (the hash is per-call, not per-session, by design).

## Install / Uninstall

Wired by `core/governance-pack/install.sh` Step 15. Three-command uninstall:

```bash
bash core/governance-pack/uninstall.sh
rm -rf ~/.claude/loop-circuit-breaker ~/.claude/sessions/*/counters.json
```

## References

- v1.7.0 fix source: [`insight_loop_circuit_breaker_v2_cap_too_tight.md`](../../) (operator memory; reproduction across Wave 4.A.1 sessions)
- Final report v2.0 plan: [`docs/research/harness-skills-required/00-final-report.md`](../../docs/research/harness-skills-required/00-final-report.md) §4 Top-5 #3 + §11 Action 2
- Charter §2.2 sub-clause #1: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
- Orchestrator bypass protocol: [`docs/conventions/loop-circuit-breaker-bypass.md`](../../docs/conventions/loop-circuit-breaker-bypass.md)
- Fansipan F10/F11/F21: see incident log
- Background-safe spawn precedent: [`opinions/safe-spawn-claude.sh`](../../opinions/)
