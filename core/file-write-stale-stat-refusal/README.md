# `file-write-stale-stat-refusal` — refuse Edit/Write when target file mtime drifted since last Read

v2.0 P1 #3. Charter §2.1 anti-fantasy + §2.2 hooks-over-rules.

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body. |
| `CLAUDE.md` | Agent-facing fragment. |
| `hooks/cache-mtime-on-read.sh` | PostToolUse(`Read`). Appends `{path,mtime,read_at}` to `~/.claude/sessions/<sid>/file-stat.cache`. |
| `hooks/file-stat-check.sh` | PreToolUse(`Edit\|Write\|MultiEdit`). Refuses on drift detection. |
| `templates/stat-cache-schema.md` | Documents the cache JSONL format. |
| `tests/test-file-stat-check.sh` | 5-case unit suite (drift, no-drift, no-cache, cooldown, bypass). |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |
| `examples/sample-output.jsonl` | privacy-clean. |

## Install

```bash
bash core/governance-pack/install.sh   # Step 13
```

The installer:
1. Copies both hooks to `~/.claude/hooks/file-write-stale-stat-refusal/`.
2. Registers PostToolUse(`Read`) → `cache-mtime-on-read.sh` AND PreToolUse(`Edit|Write|MultiEdit`) → `file-stat-check.sh` in `~/.claude/settings.json`.

## Uninstall

```bash
bash core/governance-pack/uninstall.sh
rm -rf ~/.claude/file-write-stale-stat-refusal
```

## Cooldown semantics

`STALE_COOLDOWN_SEC` (default 5) is the no-refuse window after a Read. The agent's Read → Edit cycle is typically sub-second; the cooldown swallows filesystem-clock jitter. Drift detected within the cooldown returns `decision=cooldown` (advisory) instead of refusing.

## Performance budget

| Metric | Target |
|---|---|
| Median per-call latency (cache lookup) | ≤ 5 ms |
| Hard timeout | 5000 ms |

## References

