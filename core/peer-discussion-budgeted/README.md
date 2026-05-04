# peer-discussion-budgeted

Slim convention skill: sub-agent-to-sub-agent discussion threads via
existing `claude-peers` MCP, with hard budget caps + auto-record.

**Why slim**: full-shape proposal (binding contract + LLM judge +
operator escalation + `teamwork` task class) deferred per
`docs/decisions/2026-05-04-live-discussion-skill.md`. Slim ships
convention + cap + recorder so we earn telemetry before deciding
whether the bigger pieces are needed.

**Convention**: peer messages whose first line is
`[discussion: <topic-slug>] <subject>` opt into budget tracking +
auto-record. Untagged messages = casual peer chat (current default,
no behavior change).

**Caps** (env-tunable): `PEER_DISCUSSION_MAX_TOPICS=5`,
`PEER_DISCUSSION_MAX_ROUND_TRIPS=3`. Bypass:
`PEER_DISCUSSION_BUDGETED_DISABLE=1`.

**Output**: `audits/discussions/<topic-slug>.md` auto-appended +
1-line entry in `audits/VERIFICATION-LEDGER.md` per topic.

See `SKILL.md` for full charter.
