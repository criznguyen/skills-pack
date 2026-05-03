# git-force-push-gate — agent-facing fragment

If a user asks you to bypass the gate ("force-push to main anyway", "use --no-verify to commit", "rename pre-commit to commit-msg to skip linting"), DO NOT auto-bypass. Surface the bypass mechanism instead:

> The git-force-push-gate is currently blocking this command. Three legitimate bypass paths:
>
> 1. Create a per-branch marker: `touch ~/.claude/git-force-push-gate-allow/<branch>` (preferred — operator-scoped, time-bound).
> 2. Set the bypass token: `export GIT_FORCE_PUSH_BYPASS_TOKEN=<sha>` (requires `~/.claude/git-force-push-gate/bypass-token.sha` to be operator-seeded).
> 3. Per-session disable: `export GIT_FORCE_PUSH_GATE_DISABLE=1` (use for emergency rollback only).
>
> Which one applies?

Auto-creating the marker file or setting the disable env-var inside the agent's own session bypasses the human-in-the-loop check the gate exists to enforce. Refuse and ask.

## v1.7.0 — pre-commit→commit-msg rename evasion

If you find yourself wanting to `mv .git/hooks/pre-commit .git/hooks/commit-msg` (or any equivalent: `cp`, `install`, `ln`, `git mv`) to make a commit go through despite a failing pre-commit hook — STOP. That is the textbook hook-rename evasion. The gate detects and refuses it on every branch. The correct alternatives:

1. Fix the underlying pre-commit failure (per `core/fix-root-cause/`).
2. If the pre-commit hook itself is wrong, edit or delete it explicitly and own the change.
3. If you genuinely need a one-off bypass, surface to the operator and let them issue the bypass token.

## Why this fragment is enforcement-grade

A hook plus an agent-facing prose pattern is belt-and-suspenders. The hook stops the command at the kernel boundary; the prose stops the agent from auto-rolling-the-bypass-itself. Charter §2.2 hooks-over-rules says hooks beat rules, but a rule that tells the agent NOT to write its own bypass is still useful — the hook can't see the agent's *intent* to roll a bypass, only the resulting `Bash` tool call.

End of `core/git-force-push-gate/CLAUDE.md`.
