# Cache schema — `~/.claude/sessions/<session_id>/file-stat.cache`

JSONL, one object per line. Append-only.

| Field | Type | Description |
|---|---|---|
| `path` | string | Absolute file path the agent interacted with |
| `mtime` | number | Unix epoch seconds — `stat -c %Y <path>` captured AFTER the tool ran |
| `read_at` | number | Unix epoch seconds — `date +%s` when the cache entry was written. Field name is historical — entries now come from Read, Edit, Write, and MultiEdit (v1.7.0+); for write-class events `read_at` is the post-write moment. |

## Cache-update events (v1.7.0+)

PostToolUse hook matcher: `Read|Edit|Write|MultiEdit`. The cache appends an entry after every own-tool interaction with the file. Pre-v1.7.0 the matcher was `Read` only; same-agent consecutive Edits would false-positive the drift check because the cache never advanced past the prior Read's mtime.

## Stat-check decision logic (PreToolUse, unchanged)

The PreToolUse(`Edit|Write|MultiEdit`) hook scans the cache from the bottom (most recent wins) to find the latest cache entry for the target path. Comparison logic:

- If no entry exists for the path → `decision=no-cache pass` (treats as fresh creation).
- If `(now - read_at) <= STALE_COOLDOWN_SEC` → `decision=cooldown pass` (race-condition window).
- If `current_mtime > cached_mtime` AND past cooldown → `decision=refused exit 2`.
- Otherwise → `decision=pass exit 0`.

The cache is per-session by design — cross-session contamination would defeat the cooldown invariant.
