# file-write-stale-stat-refusal — agent-facing fragment

When the file-stat-check hook refuses an edit, do NOT auto-bypass. The refusal means the file changed underneath the agent's view since the last cache update. The correct recovery is:

1. Re-Read the file (which refreshes the mtime cache).
2. Re-apply the intended Edit against the new content.

Do not set `FILE_WRITE_STALE_STAT_REFUSAL_DISABLE=1` to "make the error go away" — the hook is exactly the verify-before-claim primitive (charter §2.1) that prevents an agent from overwriting another process's edits.

## v1.7.0 — same-agent Edits no longer false-positive

Before v1.7.0 the PostToolUse cache hook only fired on `Read`. Two consecutive Edits on the same file would trip the drift check because the cache mtime was from the prior Read while the on-disk mtime reflected the agent's own first Edit. v1.7.0 expanded the matcher to `Read|Edit|Write|MultiEdit`, so the cache refreshes after every own-tool interaction with the file. Source: `insight_file_stat_refusal_cache_not_updated_on_edit.md`.

If you DO see a refusal between two of your own Edits, the most likely cause is that the **live** `~/.claude/settings.json` PostToolUse matcher still says `"Read"` (v1.6.0 default). Surface the diff to the operator — they need to run the v1.7.0 install or update the matcher manually.

End of `core/file-write-stale-stat-refusal/CLAUDE.md`.
