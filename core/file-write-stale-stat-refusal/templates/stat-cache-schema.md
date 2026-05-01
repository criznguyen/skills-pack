# Cache schema — `~/.claude/sessions/<session_id>/file-stat.cache`

JSONL, one object per line. Append-only.

| Field | Type | Description |
|---|---|---|
| `path` | string | Absolute file path the agent Read |
| `mtime` | number | Unix epoch seconds — `stat -c %Y <path>` at Read time |
| `read_at` | number | Unix epoch seconds — `date +%s` when the cache entry was written |

The PreToolUse(`Edit|Write|MultiEdit`) hook scans the cache from the bottom (most recent wins) to find the latest cache entry for the target path. Comparison logic:

- If no entry exists for the path → `decision=no-cache pass` (treats as fresh creation).
- If `(now - read_at) <= STALE_COOLDOWN_SEC` → `decision=cooldown pass` (race-condition window).
- If `current_mtime > cached_mtime` AND past cooldown → `decision=refused exit 2`.
- Otherwise → `decision=pass exit 0`.

The cache is per-session by design — cross-session contamination would defeat the cooldown invariant.
