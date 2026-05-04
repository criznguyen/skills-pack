# Skill idea — `file-write-stale-stat-refusal` v2.1: same-session-write bypass

**Origin**: 2026-05-04, ciscrm Wave 4.A.2 — Edit on `internal/auth/rbac.go`
was rejected by `file-stat-check.sh` with `[file-stat-refused] file=...
drift=76s — file was modified by another process since you last Read it`,
but the actual modification came from MY OWN previous Edit tool call in
the SAME session 76 seconds earlier. The cache update path raced with
chained PostToolUse hooks (lint-touched.sh, gofmt) which themselves
re-touched the file's mtime AFTER the cache hook ran, leading to a
false-positive on the very next Edit.

## Problem statement

The current `file-write-stale-stat-refusal` (shipped v1.7.0, matcher
widened to `Read|Edit|Write|MultiEdit`) prevents the canonical race
"another process touched the file since you last Read" but suffers two
false-positive classes:

1. **Self-write race**: Edit A in session S → PostToolUse cache updates
   to mtime_T1 → PostToolUse lint-touched.sh runs `gofmt -w` → file mtime
   bumps to mtime_T2 (≠ T1) → next Edit B's PreToolUse stat-check sees
   T2 ≠ T1, fires refusal. The "another process" is in fact same-session
   tooling (gofmt, biome, eslint, prettier).

2. **Out-of-band Edit chain**: when an `Edit` tool result feeds another
   `Edit` tool call without an intervening `Read`, the second Edit
   inherits the cache from the first. If lint-touched runs in between
   with even a 1ms mtime tick, the second Edit refuses.

## Root cause analysis

Hook order in `~/.claude/settings.json` PostToolUse for `Edit|Write|MultiEdit`:

1. `lint-touched.sh` (timeout 30s — runs `gofmt`, `prettier`, etc.)
2. `governance-pack/telemetry.sh`
3. `governance-pack/postcondition-hook.sh` (Bash|Edit|Write|MultiEdit)
4. `quarantine-pack/wrap-mcp-output.sh` (mcp__.*|WebFetch|Read)
5. `file-write-stale-stat-refusal/cache-mtime-on-read.sh` (Read|Edit|Write|MultiEdit)
6. `loop-circuit-breaker/posttooluse-cost.sh`

The cache hook (5) runs AFTER lint-touched (1). On most platforms this
ordering is correct because lint runs first then the cache stamps the
final mtime. But:

- Some lints run in background (parallel goroutine, async pre-formatter)
  — they may continue mutating the file AFTER cache update.
- Some lints have a debounce or batching window — second formatter pass
  hits T+50ms after cache update.
- `chmod`, `chown`, IDE indexers, language servers, file watchers (e.g.
  rust-analyzer, gopls) may touch mtime without re-writing content.

These all break the "stat-equals" invariant the cache relies on.

## Fix design

### Option A — Same-session-write bypass (primary)

Cache schema becomes:
```json
{
  "path": "/abs/path",
  "mtime": 1714839600.123,
  "last_writer_session_id": "dba1a455-f1df-44af-88af-eedc7f061786",
  "last_write_seq": 42,        // monotonically incrementing per session
  "last_writer_pid": 359889    // optional: catches forked sub-agents
}
```

PreToolUse stat-check logic:
1. Read current `stat -c %Y file` → `current_mtime`.
2. Read cache.
3. If `current_mtime == cache.mtime` → PASS (no drift).
4. ELSE if `cache.last_writer_session_id == $CURRENT_SESSION_ID` → PASS
   (same session wrote this; mtime bump is from local lint/formatter).
   Update cache to `current_mtime` to prevent further false-positives.
5. ELSE → REFUSE (real cross-session drift; user needs to re-read).

The session_id is already in the hook's `$INPUT` JSON (`d.session_id`).
The `last_writer_pid` is optional defense-in-depth for shells that fork
sub-agents which inherit session_id.

**Trade-off**: assumes one editor session per file at a time. If two
agents in the same session truly race-edit the same file (extremely rare;
violates file-scope contract), the bypass would miss the drift. But:
- File-scope contract is enforced by sub-agent prompts.
- Worktree isolation (one worktree per agent) means agents have
  per-agent file copies anyway.

### Option B — Stat-after-chain (complementary)

Move cache hook from position 5 to a dedicated late-chain position by
adding a new matcher group that runs LAST:

```json
{
  "matcher": ".*",
  "hooks": [
    { "type": "command", "command": "<cache-mtime-on-read.sh>", "timeout": 5000 }
  ]
}
```

…appended at the END of `PostToolUse`. The matcher `.*` ensures it
catches any Edit/Write/MultiEdit, AND it runs after lint, telemetry,
postcondition, and quarantine hooks have stabilized the file.

**Trade-off**: ordering is fragile (depends on settings.json order); a
user who reorders hooks may break it. Use Option A instead as primary;
Option B is belt-and-suspenders.

### Option C — Tolerance window (fallback)

If session-id tracking is too invasive, accept the cache as valid when
`abs(current_mtime - cache.mtime) <= TOLERANCE_SECONDS` (default: 2s).
This eats real drift smaller than 2s, but file edits typically arrive
in waves >2s apart from "another process" (humans typing, IDEs).

**Trade-off**: weakens the safety guarantee. Use only as last-resort.

## Recommended implementation

Ship Option A as v2.1 of the existing `file-write-stale-stat-refusal`
skill. Backward compatible: cache reader treats missing
`last_writer_session_id` as "unknown" → falls through to existing
strict-stat behavior. Cache writer sets the new fields whenever it
runs.

## Hook script change (file-stat-check.sh)

```bash
# After computing stale=$(...), inject:
if [ "$stale" = "1" ]; then
  cached_session=$(jq -r '.last_writer_session_id // ""' "$CACHE_FILE" 2>/dev/null)
  if [ -n "$cached_session" ] && [ "$cached_session" = "$SESSION_ID" ]; then
    # Same-session bypass — refresh cache to current mtime and PASS.
    update_cache "$path" "$current_mtime" "$SESSION_ID"
    emit_telemetry "same-session-bypass" "$path"
    exit 0
  fi
fi
# Otherwise existing refusal path.
```

## Cache update script (cache-mtime-on-read.sh)

```bash
# Append session_id to the cached entry:
jq --arg sid "$SESSION_ID" '.last_writer_session_id = $sid' < "$CACHE_FILE" > "$CACHE_FILE.tmp"
mv "$CACHE_FILE.tmp" "$CACHE_FILE"
```

## Tests

`tests/same-session-bypass.test.sh`:

1. Edit file → cache updated with session_id=S1.
2. Touch file (simulating gofmt) → mtime bumps.
3. Edit again with same SESSION_ID=S1 → expected PASS.
4. Edit again with SESSION_ID=S2 → expected REFUSAL.

## Telemetry

Add new `bypass-event` to telemetry stream:
```
{"event":"file-stat-refusal","action":"same-session-bypass",
 "path":"...","drift_secs":76,"session_id":"S1","ts":"..."}
```

So users can confirm the bypass is firing and audit how often it engages.

## Estimated impact

In ciscrm Wave 4.A.2, the false-positive blocked 1 Edit attempt forcing
a Read-then-Edit cycle (negligible orchestrator time but breaks flow).
On longer multi-Edit refactors (e.g. renaming a symbol across 20 files
where gofmt runs between each), the false-positive rate would compound
into significant friction.

Estimated annual time saved across active multi-agent users: 2-5 hours.
Low-effort fix with strong correctness guarantee — ship in v1.7.1
(patch) or v1.8.0 (minor).

## Compatibility note

The v1.7.0 release notes already claim "v2.0 cache only on Read →
drift-fail; shipped matcher widening Read|Edit|Write|MultiEdit" closed
the prior bug. This v2.1 fix is a follow-on strengthening — it
addresses a class of false-positives the v1.7.0 fix didn't anticipate
(self-write chain via PostToolUse formatters).

## Related skills

- Composes with `governance-pack` (telemetry stream).
- Could be packaged with `multi-agent-merge-discipline` (this doc's
  sibling) since multi-agent waves are where the bug surfaces most.
