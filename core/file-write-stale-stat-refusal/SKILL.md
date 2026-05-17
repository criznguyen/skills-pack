---
name: file-write-stale-stat-refusal
description: PreToolUse hook (matcher Edit|Write|MultiEdit) refusing writes when the target file's mtime drifted since the agent last Read it. v1.7.0 — companion PostToolUse hook now matches Read|Edit|Write|MultiEdit so consecutive same-agent Edits no longer false-positive (cache mtime advances after every own-write). 5-second race-condition cooldown documented. Hard-block exit 2 with stderr advisory ("file was modified by another process since you last Read it; re-read before editing"). v2.0 P1 #3.
paths: []
when_to_use: Background hook — fires automatically on Edit/Write/MultiEdit; never invoked directly by the user.
disable-model-invocation: true
type: governance
tools: Edit, Write, MultiEdit, Read
model: opus
blast_radius: local-write
last-validated: 2026-05-04
---

# file-write-stale-stat-refusal

Charter §2.1 anti-fantasy + §2.2 hooks-over-rules. The "read-before-edit" discipline already lands at the prose layer (`pre-edit-stash.sh` from core-config); this hook closes the **stale-stat** gap: an Edit on a file whose mtime drifted since the agent's last Read of that path is refused, because the agent is editing a stale view of the world.

Two hooks ship in this skill:

1. **`hooks/cache-mtime-on-read.sh`** — PostToolUse(`Read|Edit|Write|MultiEdit`). Populates `~/.claude/sessions/<session_id>/file-stat.cache` with `{path, mtime}` after every own-tool interaction with the file. v1.7.0 expanded the matcher from `Read` only — without that, the agent's own consecutive Edits looked like external drift to the PreToolUse check.
2. **`hooks/file-stat-check.sh`** — PreToolUse(`Edit|Write|MultiEdit`). Looks up cached mtime; compares to current `stat -c %Y <path>`; refuses if drift > 0 AND the last cache update was > `STALE_COOLDOWN_SEC` (default 5) seconds ago.

The 5-second cooldown is the race-condition concession (the agent often Reads → Edits within milliseconds; in that window an external mtime change is unlikely and the cooldown prevents false positives from filesystem clock skew).

### v1.7.0 — why the cache also updates on Edit/Write/MultiEdit

Source: `insight_file_stat_refusal_cache_not_updated_on_edit.md`. Before v1.7.0 the cache was Read-only:

```
Read X     → cache mtime_at_read
Edit X #1  → file mtime advances on disk; cache UNCHANGED
Edit X #2  → check sees mtime_now > cached mtime_at_read → REFUSED (false positive)
```

The hook had no way to distinguish "I just modified it" from "another process modified it." Adding Edit/Write/MultiEdit to the cache-update matcher closes the same-agent false positive. The race window between PreToolUse stat check and PostToolUse cache update is milliseconds; a malicious external write that lands in that gap will slip past until the next agent action on the file.

## When to use

Auto-installed by `core/governance-pack/install.sh` Step 13. Operators who run sessions where:

- Multiple agents share a working tree (worktree-spawn pattern), OR
- A separate process (linter, formatter, codegen) writes files between the agent's Read and Edit

are protected against silent stale-write overwrites.

## When NOT to use

- **For a Write to a not-yet-existing path.** The hook checks for the cache entry first; if no Read has been registered for the path, the hook treats the write as a fresh creation (not a stale overwrite). This is the desired semantic.
- **For high-churn auto-generated files.** Add the path glob to `~/.claude/file-write-stale-stat-refusal/skip-paths.txt` to opt out per file.

## Bypass

```bash
export FILE_WRITE_STALE_STAT_REFUSAL_DISABLE=1
```

## Cache schema

`~/.claude/sessions/<session_id>/file-stat.cache` is a JSONL file, one line per cache event:

```json
{"path":"/repo/src/x.go","mtime":1714400000,"read_at":1714400001}
```

The hook scans the cache from the bottom (most recent wins) to find the latest cache event for the path under check. Cache events come from Read, Edit, Write, and MultiEdit (v1.7.0+).

## Forbidden in hook bodies (TM4)

`hooks/*.sh` are shell + jq + python3-fallback + grep + stat only. Enforced by `tests/test-no-claude-spawn.sh`.

## Telemetry

```json
{"event":"file-stat-check","ts":"...","tool":"Edit","decision":"refused|pass|bypass|cooldown|no-cache","file_path":"...","drift_seconds":12,"session_id":"..."}
```

Privacy invariant: only the path, decision, and drift seconds are persisted. Path is operator-visible by default.

## Install / Uninstall

Wired by `core/governance-pack/install.sh` Step 13. Three-command uninstall:

```bash
bash core/governance-pack/uninstall.sh
rm -rf ~/.claude/file-write-stale-stat-refusal ~/.claude/sessions/*/file-stat.cache
```

## References

- Final report v2.0 plan: [`docs/research/harness-skills-required/00-final-report.md`](../../docs/research/harness-skills-required/00-final-report.md) §5 P1 #3
- Charter §2.1 anti-fantasy: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
- Companion to: [`core/core-config/hooks/pre-edit-stash.sh`](../core-config/hooks/pre-edit-stash.sh)
