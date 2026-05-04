# peer-discussion-budgeted — agent-facing fragment

If you need to coordinate with another sub-agent on a NAMED topic, you
MAY emit a peer message via `mcp__claude-peers__send_message` with the
first line in the form:

```
[discussion: <topic-slug>] <one-line-subject>

<body>
```

This opts your message into:
1. Hard budget caps (default 5 topics/session × 3 round-trips/topic).
2. Auto-recording into `audits/discussions/<topic-slug>.md`.

If you exceed the cap you will receive an exit-2 stderr refusal. The
correct recovery is to:

1. Check the existing record at `audits/discussions/<topic-slug>.md`
   to see what has already been said.
2. Make your decision unilaterally based on the record, OR
3. Surface a structured failure-report to the orchestrator with what
   blocked + what your tentative decision is + why peer agreement
   wasn't reached. Do NOT keep asking peers indefinitely.

Casual peer messages (no `[discussion:...]` prefix) are NOT counted
or recorded. Use them freely.

End of `core/peer-discussion-budgeted/CLAUDE.md`.
