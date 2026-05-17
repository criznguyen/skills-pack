---
name: peer-discussion-budgeted
description: Slim convention skill for sub-agent-to-sub-agent live discussion via the existing `claude-peers` MCP, with hard budget caps to prevent recursive-discussion tarpits. Sub-agents opt-in by prefixing messages with `[discussion: <topic-slug>] <subject>\n<body>`. PreToolUse hook caps total topics per session (default 5) and round-trips per topic (default 3); PostToolUse hook auto-appends each tagged message to `audits/discussions/<topic-slug>.md` plus 1-line entry in `audits/VERIFICATION-LEDGER.md`. Untagged peer messages (casual coordination) are not counted or recorded. Advisory output only — no binding contract, no rebroadcast, no operator escalation in v1.9. Slim variant of the deferred full-shape proposal `docs/decisions/2026-05-04-live-discussion-skill.md`.
paths: []
when_to_use: Auto-fires via budget-gate hook on tagged `[discussion: <topic>]` peer messages; never invoked directly as a slash command.
disable-model-invocation: true
type: governance
tools: mcp__claude-peers__send_message, mcp__claude-peers__check_messages
model: opus
blast_radius: local-write
last-validated: 2026-05-04
---

# peer-discussion-budgeted

Origin: live ciscrm Wave 4.A.2 retrospective surfaced cross-domain
coordination cases where parallel sub-agents independently inferred
contracts that turned out to disagree (MK-Journeys agent omitted 4
hooks because it didn't see Marketing's other agents' BE intent;
Audience agent diverged on ctxq regen pattern). Ad-hoc peer messages
via `claude-peers` MCP exist but had no convention or budget guard,
so the temptation to recurse into "we should discuss this further" is
unbounded. This skill closes that gap with the slimmest addressable
slice — convention + caps + auto-record — earning telemetry toward
deciding whether the deferred full-shape pieces (binding contract,
LLM judge, operator escalation, dedicated `teamwork` task class) ever
need to ship.

## Convention

A sub-agent that needs to coordinate with another sub-agent on a
named topic prefixes the peer message with:

```
[discussion: <topic-slug>] <one-line-subject>

<message body, can span multiple lines>
```

- `<topic-slug>` is `[a-z0-9][a-z0-9-]{2,63}` — kebab-case identifier.
- The first line is the discussion header; anything after the blank
  line is body content. Body can be empty for ack-style messages.
- Untagged peer messages (no `[discussion: ...]` prefix) are NOT
  budgeted, NOT recorded, NOT inspected by this skill. They behave
  as casual peer chat (current default).

A "discussion" = the bag of all messages sharing the same topic-slug
within the session. A "round-trip" = each pair of (msg-in / msg-out)
between two peer agents on the same topic, regardless of order.

## Budget enforcement (PreToolUse)

`hooks/budget-gate.sh` runs as PreToolUse(`mcp__claude-peers__send_message`).

- Inspect `tool_input.message`. If first line does NOT start with
  `[discussion: ...]`, exit 0 (casual message → not budgeted).
- Else extract `<topic-slug>`. Read counter file
  `~/.claude/sessions/<session-id>/discussion-counters.json`.
- Refuse with exit 2 if any of these holds:
  - **New topic but topic_count >= MAX_TOPICS_PER_SESSION** (default 5).
  - **Existing topic with round_trips >= MAX_ROUND_TRIPS_PER_TOPIC**
    (default 3, i.e. 6 message exchanges total counting both directions).
- Else update counter (increment round_trips for existing topic OR
  initialize new topic with round_trips=1) and exit 0.

Caps tunable via env:
- `PEER_DISCUSSION_MAX_TOPICS` (default 5)
- `PEER_DISCUSSION_MAX_ROUND_TRIPS` (default 3)

Bypass: `PEER_DISCUSSION_BUDGETED_DISABLE=1` for emergency override.

Refusal stderr message:
```
[peer-discussion-budgeted] halted: topic=<slug> round_trips=<N> ceiling=<M>
                            OR topic_count=<X> ceiling=<MAX_TOPICS>
Use plain peer messages (no [discussion:...] prefix) for casual coordination,
or surface the blocker to the orchestrator if N rounds did not converge.
```

## Discussion recorder (PostToolUse)

`hooks/discussion-recorder.sh` runs as
PostToolUse(`mcp__claude-peers__send_message|mcp__claude-peers__check_messages`).

- For each tagged message (sent or received), append a record block to
  `$CLAUDE_PROJECT_DIR/audits/discussions/<topic-slug>.md`.
- Block format:
  ```
  ## <ISO-8601 timestamp> — <from-agent-id-short> → <to-agent-id-short>
  
  > Subject: <one-line-subject>
  
  <body>
  
  ---
  ```
- If file does not exist, create with a top-banner:
  ```
  # Discussion: <topic-slug>
  
  Started: <ts>  ·  Wave: <env $CLAUDE_WAVE_ID or "unknown">
  Convention: peer-discussion-budgeted v1.9
  Budget: <topic_count>/<MAX_TOPICS> topics · <round_trips>/<MAX_ROUND_TRIPS> RT for this topic
  
  ---
  ```

- Also append a 1-line entry to
  `$CLAUDE_PROJECT_DIR/audits/VERIFICATION-LEDGER.md` once per topic
  (first message only):
  `[discussion] <topic-slug> opened <ts> by <from> → see audits/discussions/<topic-slug>.md`

The recorder is idempotent: re-running on the same message (same
ts+from+to+content hash) is a no-op.

## When NOT to use

- Inside a single agent's own work (you talk to yourself by writing
  notes, not sending peer messages).
- Operator-supplied tasks where the answer is "just ask the operator"
  — use AskUserQuestion or surface in the agent's failure report.
- Mass-broadcast announcements — that's not "discussion", that's
  notification; outside this skill's scope.

## Why advisory-only in v1.9

The deferred full-shape proposal had:
- Binding contract update + commit + rebroadcast — needs `agent.pause()`
  / `agent.broadcast()` harness primitives not yet documented.
- LLM judge agent for adversarial debate — adds 1 round of cost per
  unresolved discussion before falling back; cost-benefit unclear
  without 2-3 waves of telemetry.
- Operator escalation at hard timeout — easy to add later, but
  premature to wire when peer-only hasn't been measured to actually
  fail.

Slim variant ships only the convention + cap + auto-record so we can
measure: how often do agents emit `[discussion:...]` messages? what
topics? how many round-trips before agents converge? do agents
commit useful contract knowledge into the discussion record that
later waves can re-read? After 2-3 ciscrm waves of telemetry, the
deferred pieces get re-evaluated against measured pain.

## Adoption checklist (per project)

1. `mkdir -p audits/discussions`
2. Add to project `AGENTS.md`:
   > Sub-agents that need cross-domain coordination MAY emit peer
   > messages prefixed `[discussion: <topic-slug>]`. Budget caps and
   > auto-record handled by `peer-discussion-budgeted` skill (global
   > install). See `audits/discussions/` for record archive.
3. Wire hooks in `.claude/settings.json` (or rely on global install).

## Verify gates

```bash
# Casual peer message → not budgeted
echo '{"tool_name":"mcp__claude-peers__send_message","tool_input":{"to":"foo","message":"hi how are you"}}' | hooks/budget-gate.sh
# expected: exit 0, no counter update

# Tagged discussion message → budgeted
echo '{"tool_name":"mcp__claude-peers__send_message","tool_input":{"to":"foo","message":"[discussion: my-topic] subject\n\nbody"}}' | hooks/budget-gate.sh
# expected: exit 0 first time; exit 2 on the 4th call to same topic

# 6 distinct topics → 6th refused
for i in 1 2 3 4 5 6; do
  echo "{\"tool_name\":\"mcp__claude-peers__send_message\",\"tool_input\":{\"to\":\"x\",\"message\":\"[discussion: t-$i] s\"}}" | hooks/budget-gate.sh
done
# expected: t-1..t-5 pass; t-6 refused
```

## Telemetry events (reuses governance-pack stream)

- `peer-discussion-budgeted action=opened topic=<slug>` — first message of a topic
- `peer-discussion-budgeted action=round-trip topic=<slug> rt=<N>` — subsequent
- `peer-discussion-budgeted action=halt-topic-cap topic=<slug>` — RT cap hit
- `peer-discussion-budgeted action=halt-session-cap topic_count=<N>` — topics cap hit
- `peer-discussion-budgeted action=recorded topic=<slug> message_hash=<h>` — auto-record write

## Related

- Composes with `governance-pack` (telemetry stream + per-project allowlist pattern).
- Composes with `loop-circuit-breaker` (sibling counter family).
- Origin VERDICT: `docs/decisions/2026-05-04-live-discussion-skill.md`.
- Origin pain signal: live ciscrm Wave 4.A.2 retrospective.
