# multi-agent-merge-discipline

Cuts orchestrator merge tax when running 3+ parallel sub-agent worktrees.

**Part A** (PreToolUse hook): strips per-project allowlisted auto-
generated files from sub-agent commits → orchestrator regenerates union
post-merge instead of resolving textual conflicts on derivable artifacts.

**Part B** (handoff manifest): structured JSON declaring additions to
shared APPEND-ONLY files (RBAC, routes, wiring) → orchestrator merges
programmatically rather than textual git merge.

See `SKILL.md` for full charter, setup, and verify gates.

Origin doc: `docs/research/v1.8-ideas/multi-agent-merge-discipline.md`.
