# `installed-hook-drift` — sanity check between installed hooks and canonical source

v1.7.0. v2.2-candidate close-out from `project_claude_skills_v2_0_shipped.md`.

When the agent says "the loop-circuit-breaker hook is broken," the most common cause is local drift: the installed copy at `~/.claude/hooks/loop-circuit-breaker/pretooluse-count-hash.sh` no longer matches the canonical `<repo>/core/loop-circuit-breaker/hooks/pretooluse-count-hash.sh`. Causes include manual edit, partial git pull without re-install, or third-party tool overwrites.

This skill ships a reporter that compares both sides and emits JSONL findings. Reporter — not enforcer.

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body. |
| `CLAUDE.md` | Agent-facing fragment. |
| `hooks/check-drift.sh` | The reporter. JSONL on stdout, exit 0 always. |
| `templates/settings-snippet.json` | Optional SessionStart wiring (operator opt-in). |
| `tests/test-check-drift.sh` | 4-case suite (no-drift, drift, orphan, custom-orphan). |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |
| `examples/sample-output.jsonl` | Sample drift report. |

## Usage

```bash
# Default: REPO_ROOT inferred from script location (~/src/claude-skills/core/installed-hook-drift/hooks/check-drift.sh → ~/src/claude-skills).
bash core/installed-hook-drift/hooks/check-drift.sh

# Explicit REPO_ROOT.
bash core/installed-hook-drift/hooks/check-drift.sh /path/to/claude-skills

# Or via env.
CLAUDE_SKILLS_REPO_ROOT=/path/to/claude-skills bash core/installed-hook-drift/hooks/check-drift.sh
```

Sample output (one line per drift):

```json
{"status":"drift","installed":"/home/u/.claude/hooks/loop-circuit-breaker/pretooluse-count-hash.sh","canonical":"/home/u/src/claude-skills/core/loop-circuit-breaker/hooks/pretooluse-count-hash.sh","installed_sha":"a1b2c3...","canonical_sha":"c3d4e5..."}
```

## Performance budget

| Metric | Target |
|---|---|
| Median per-hook sha256 + compare | ≤ 5 ms |
| Total runtime (typical install ~12 hooks) | ≤ 100 ms |

## Install

This skill is **NOT** auto-installed by `core/governance-pack/install.sh`. The reporter is opt-in:

- Run on demand: `bash core/installed-hook-drift/hooks/check-drift.sh`
- Or wire to SessionStart by jq-merging `templates/settings-snippet.json` into `~/.claude/settings.json`.

## References

- Source: `project_claude_skills_v2_0_shipped.md` v2.2 candidate
- Sister: `core/governance-pack/install.sh`
