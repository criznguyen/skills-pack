---
name: worktree
description: Spawn / list / cleanup git worktrees with auto-generated coordination CLAUDE.md. Use when you want to run multiple Claude sessions in parallel on isolated branches. Hard-capped at 3 parallel worktrees per repo (v1) — see core/worktree-spawn/CAVEAT.md before raising the cap.
argument-hint: <subcommand> [args]
allowed-tools: Bash(./core/worktree-spawn/scripts/*.sh:*), Bash(git worktree:*), Bash(git status:*)
---

# /worktree — managed parallel worktrees

Wraps `core/worktree-spawn/scripts/{spawn,cleanup,list}.sh` so Claude can drive
the parallel-worktree workflow without re-deriving the safety rules each time.

## Subcommands

```
/worktree spawn <task-id> [N=2] [--scope "..."]
/worktree list
/worktree cleanup <branch-or-path> [--force] [--keep-branch]
```

## When to use

- You have **>1 independent slice** of work for the same task that can proceed
  without waiting on each other (e.g. backend + frontend; two parallel refactors;
  spec exploration vs. implementation spike).
- You have **read `CAVEAT.md`** and confirmed N>1 is the right call. Most tasks
  don't need parallel worktrees — see "When 1 beats N" in CAVEAT.md.

## When NOT to use

- A single small feature (≤3 files). Overhead exceeds payoff.
- Work that is sequential by nature (foo must land before bar can compile).
- You don't have the supervisor bandwidth to review N parallel streams of output.

## Behaviour

- **`spawn`** — creates `N` worktrees under `.worktrees/<task-id>-<seq>/` on
  branches `wt/<task-id>-<seq>`. Hard cap of 3 enforced (exit code 3 with the
  message *"cap reached; merge or delete one before spawning more"*). Each new
  worktree gets a `CLAUDE.md` (sibling list, scope, merge order) and a
  `FEATURE-CHARTER.md` (problem statement, success criteria, non-goals, verify
  command — to be filled in before implementation starts).
- **`list`** — ps-style table: branch, path, dirty/clean, ahead-of-main, age.
  Use this before spawning more — if siblings are stale, merge or cleanup first.
- **`cleanup`** — refuses to remove worktrees with uncommitted changes or
  unmerged commits. Pass `--force` to override (with a warning), `--keep-branch`
  to keep the branch after removing the worktree.

## Args

- `<task-id>` — short, kebab-case identifier (e.g. `auth-rewrite`, `p0-04`).
  Becomes the branch suffix and the worktree dir name.
- `[N]` — number of worktrees, default 2, hard max 3.
- `--scope "..."` — one-line description injected into each worktree's
  `CLAUDE.md` and `FEATURE-CHARTER.md`. Optional but strongly recommended;
  worktrees without a scope tend to drift.

## Env overrides (use sparingly)

- `WT_BRANCH_PREFIX` — default `wt/`
- `WT_ROOT` — default `.worktrees`
- `WT_BASE_REF` — default `HEAD` of current branch
- `WT_CAP` — default `3`. **Do NOT raise without reading `CAVEAT.md`.**
  Above 3, the supervisor's own context budget is the bottleneck.

## Examples

```
/worktree spawn p0-04 3 --scope "build worktree-spawn primitive (script + cmd + tests)"
/worktree list
/worktree cleanup wt/p0-04-2
/worktree cleanup .worktrees/p0-04-3 --force --keep-branch
```

## Implementation

This command shells out to the scripts under `core/worktree-spawn/scripts/`.
Read those for the exact behaviour, exit codes, and safety checks:

- `scripts/spawn.sh`   — hard cap, sequential branch naming, coordination CLAUDE.md
- `scripts/list.sh`    — status table; `--json` for programmatic use
- `scripts/cleanup.sh` — safe removal; refuses dirty/unmerged; `--force` overrides

## Citations

- Superpowers Phase 2: parallel worktree workflow ([Source: https://github.com/obra/superpowers](https://github.com/obra/superpowers); ~170k★ as of 2026-04-28).
- 3-cap rationale: roadmap §2.4 + charter §6 (supervisor context budget; merge wall).
- The Cherny "259 PRs in 30 days" headline is **vendor-internal** and intentionally NOT used here ([Source: docs/review/v1.1/CITATIONS-FIXED.md §5; CITE-4](file:///home/criznguyen/projects/claude-skills/docs/review/v1.1/CITATIONS-FIXED.md)).
