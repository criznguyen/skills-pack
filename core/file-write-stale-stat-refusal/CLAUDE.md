# file-write-stale-stat-refusal — agent-facing fragment

When the file-stat-check hook refuses an edit, do NOT auto-bypass. The refusal means the file changed underneath the agent's view since the last Read. The correct recovery is:

1. Re-Read the file (which refreshes the mtime cache).
2. Re-apply the intended Edit against the new content.

Do not set `FILE_WRITE_STALE_STAT_REFUSAL_DISABLE=1` to "make the error go away" — the hook is exactly the verify-before-claim primitive (charter §2.1) that prevents an agent from overwriting another process's edits.

End of `core/file-write-stale-stat-refusal/CLAUDE.md`.
