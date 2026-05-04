# multi-agent-merge-discipline — agent-facing fragment

When committing as a sub-agent in a worktree, the PreToolUse hook
`pre-commit-strip-gen.sh` MAY unstage auto-generated files from your
staging area (sqlc gen, ctxq, proto, OpenAPI clients, etc. — per the
project's `.claude/skills/multi-agent-merge-discipline/gen-paths.txt`).
This is INTENTIONAL.

You will see stderr like:

```
[multi-agent-merge-discipline] stripped 7 auto-gen files from staging
(will regen post-merge): internal/platform/db/gen/...
```

Do NOT re-add those files. They are derivable from your hand-written
sources (`db/queries/*.sql`, `proto/*.proto`, etc.) which ARE in your
commit. The orchestrator runs `make generate` after merging your
branch and produces the union of all sub-agents' additions.

If you receive a commit-empty error after the strip, your changes were
ENTIRELY in auto-generated files — that's a sub-agent task design bug,
not a strip bug. Re-examine the task: if it's "regenerate gen files",
the orchestrator should do it post-merge, not a sub-agent.

End of `core/multi-agent-merge-discipline/CLAUDE.md`.
