---
name: installed-hook-drift
description: Reporter that compares each installed hook in `~/.claude/hooks/<group>/<hook>.sh` against the canonical version in `<repo>/core/<group>/hooks/<hook>.sh` of the claude-skills source tree. Flags drift (sha256 mismatch) and orphans (installed hook with no canonical counterpart). Output is JSONL on stdout; exit 0 always (this is a reporter, not a gate). Useful as a sanity check before filing "skill is broken" issues — local drift is a common cause of unexplained skill behavior. v1.7.0 closes the v2.2 candidate from project_claude_skills_v2_0_shipped.md.
type: governance
tools: Bash, Read, Grep
model: opus
blast_radius: read-only
last-validated: 2026-05-04
---

# installed-hook-drift

A claude-skills hook is two files:

1. **Canonical source** at `<repo>/core/<group>/hooks/<hook>.sh` (this repo).
2. **Installed copy** at `~/.claude/hooks/<group>/<hook>.sh` (placed there by `core/governance-pack/install.sh`).

When the operator manually edits a hook ("just trying something"), runs an old `git pull` without re-installing, or a third-party tool overwrites the installed copy, the two files drift apart. The skill stops behaving like the documented spec and the operator may file a "skill is broken" issue when the actual cause is local drift.

This skill ships a reporter. It does NOT auto-fix and it does NOT enforce — operator decides what to do with the report.

## What it does

`hooks/check-drift.sh` walks `~/.claude/hooks/*/`. For each installed `*.sh` it:

1. Resolves the canonical path: `<REPO_ROOT>/core/<group>/hooks/<basename>.sh` where `<group>` is the directory name under `~/.claude/hooks/` and `<REPO_ROOT>` comes from arg 1 OR `CLAUDE_SKILLS_REPO_ROOT` env OR the script's own location.
2. If the canonical file does not exist → emits `{"status":"orphan","installed":...,"canonical":null,...}`.
3. If both exist but sha256 differ → emits `{"status":"drift","installed":...,"canonical":...,"installed_sha":...,"canonical_sha":...}`.
4. If sha256 match → silent (no drift).

Always exits 0. Output goes to stdout as JSONL. Each line is one finding.

## When to use

- **Sanity check before filing a "skill is broken" issue.** Run the script; if any drift is reported, it's likely local — not a real bug.
- **Post-`git pull` verification** that the operator re-ran the install script. Drift after a pull means the installed hooks are still on the previous version.
- **Multi-machine consistency check.** Run it on each box; the JSONL output is diffable.
- **CI gate (optional).** A CI job that re-runs `install.sh` then `check-drift.sh` and asserts zero output catches install regressions.

## When NOT to use

- **As an automatic enforcement gate.** Operators legitimately edit installed hooks (e.g. add a project-specific exception). Auto-overwriting their edits would be hostile. The reporter respects operator agency.
- **For non-skill hooks.** Hooks installed under `~/.claude/hooks/<group>/` where `<group>` does not correspond to any `core/<group>/` skill are reported as `orphan` so the operator sees them; they are not necessarily wrong.

## Usage

```bash
# Default: REPO_ROOT inferred from script location.
bash core/installed-hook-drift/hooks/check-drift.sh

# Explicit REPO_ROOT (e.g. for a clone in a non-standard location).
bash core/installed-hook-drift/hooks/check-drift.sh /path/to/claude-skills

# Or via env.
CLAUDE_SKILLS_REPO_ROOT=/path/to/claude-skills bash core/installed-hook-drift/hooks/check-drift.sh
```

Sample output:

```json
{"status":"drift","installed":"/home/u/.claude/hooks/loop-circuit-breaker/pretooluse-count-hash.sh","canonical":"/home/u/src/claude-skills/core/loop-circuit-breaker/hooks/pretooluse-count-hash.sh","installed_sha":"a1b2...","canonical_sha":"c3d4..."}
{"status":"orphan","installed":"/home/u/.claude/hooks/custom/my-personal-hook.sh","canonical":null}
```

## Optional SessionStart wiring

`templates/settings-snippet.json` is a settings.json snippet that runs the reporter on SessionStart and surfaces drift via stderr. Operator opts in by jq-merging the snippet into `~/.claude/settings.json`. Off by default — most operators don't want a session-start summary on every fresh session.

## Forbidden in hook bodies (TM4)

`hooks/check-drift.sh` is shell + sha256sum/shasum + python3-fallback + grep + stat only. No LLM invocation, no sub-agent. Enforced by `tests/test-no-claude-spawn.sh`.

## References

- v1.7.0 source: `project_claude_skills_v2_0_shipped.md` v2.2 candidate "installed-hook-drift detector"
- Sister skill: `core/governance-pack/install.sh` (the canonical hook installer)
- Charter §2.2 hooks-over-rules — this skill is the meta-check that the hooks the rule depends on actually match the canonical source.
