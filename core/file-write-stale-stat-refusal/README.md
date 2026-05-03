# `file-write-stale-stat-refusal` — refuse Edit/Write when target file mtime drifted since last own-action

v2.0 P1 #3. Charter §2.1 anti-fantasy + §2.2 hooks-over-rules.

v1.7.0: cache also updates on Edit/Write/MultiEdit so consecutive same-agent Edits don't false-positive. Source: `insight_file_stat_refusal_cache_not_updated_on_edit.md`.

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body. |
| `CLAUDE.md` | Agent-facing fragment. |
| `hooks/cache-mtime-on-read.sh` | PostToolUse(`Read\|Edit\|Write\|MultiEdit`) — v1.7.0+. Appends `{path,mtime,read_at}` to `~/.claude/sessions/<sid>/file-stat.cache` after every own-tool action on the file. |
| `hooks/file-stat-check.sh` | PreToolUse(`Edit\|Write\|MultiEdit`). Refuses on drift detection. |
| `templates/stat-cache-schema.md` | Documents the cache JSONL format. |
| `tests/test-file-stat-check.sh` | 6-case unit suite (drift, no-drift, no-cache, cooldown, bypass, v1.7.0 same-agent-Edit). |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |
| `examples/sample-output.jsonl` | privacy-clean. |

## Install

```bash
bash core/governance-pack/install.sh   # Step 13
```

The installer:
1. Copies both hooks to `~/.claude/hooks/file-write-stale-stat-refusal/`.
2. Registers PostToolUse(`Read|Edit|Write|MultiEdit`) → `cache-mtime-on-read.sh` AND PreToolUse(`Edit|Write|MultiEdit`) → `file-stat-check.sh` in `~/.claude/settings.json`.

### Migrating from v1.6.0 install

If your existing `~/.claude/settings.json` has the v1.6.0 PostToolUse matcher `"Read"` for this skill, change it to `"Read|Edit|Write|MultiEdit"` (or re-run the v1.7.0 install). Without that change, the v1.7.0 hook still works correctly (the matcher decides which events fire the hook; the hook's internal case-match accepts either the old or new set), but Edit/Write/MultiEdit events will not refresh the cache and the v1.6.0 same-agent-edit false positive persists.

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

- Final report: [`docs/research/harness-skills-required/00-final-report.md`](../../docs/research/harness-skills-required/00-final-report.md) §5 P1 #3
