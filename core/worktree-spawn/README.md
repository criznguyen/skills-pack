# `worktree-spawn` — capped parallel worktrees with auto-coordination

**Partition:** `core/` (universal — no operator-specific defaults).
**Hard cap:** 3 active spawned worktrees per repo. Configurable via `WT_CAP` but
**do not raise without reading `CAVEAT.md`** first.

## What this is

A `/worktree` slash-command + 3 small shell scripts that drive
`git worktree` with two safety properties most ad-hoc setups lack:

1. **A hard cap on parallel worktrees**, with a clear error message at the 4th.
2. **An auto-generated per-worktree `CLAUDE.md`** that tells each Claude session
   it has siblings, what those siblings are working on, and the recommended
   merge order — so parallel agents don't redundantly re-derive each other's work.

Plus a **safe cleanup** that refuses to remove worktrees with uncommitted or
unmerged work (overrideable with `--force`).

## Why a cap

The pattern is real. The headline number isn't.

The "use git worktrees and run dozens of Claudes" framing has been propagated
widely from Boris Cherny's public posts. The original "259 PRs in 30 days"
figure is **vendor-internal** — it reflects internal Anthropic API quotas,
1M-context model access, and dogfooding tooling that does not generalise to
external users
([CITATIONS-FIXED.md §5](file:///home/criznguyen/projects/claude-skills/docs/review/v1.1/CITATIONS-FIXED.md);
HN discussion 46407967). v1 of this skill **drops that framing entirely** and
treats it as a marketing artifact, not an SLO.

The pattern itself is independently corroborated:

- **`obra/superpowers`** ships `using-git-worktrees` as **Phase 2** of its
  7-phase workflow — ~170k★ on GitHub, MIT-licensed, accepted into
  `anthropics/claude-plugins-official` 2026-01-15
  ([Source](https://github.com/obra/superpowers);
   [SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/using-git-worktrees/SKILL.md)).
  Anthropic-endorsed via inclusion in the official marketplace, not just
  Cherny-endorsed.
- **CN community practitioners** (`blog.ccino.org`, Meta-engineer commentary,
  `garrytan/gstack` 85k★) cite the same one-task-per-branch + worktree pattern,
  arrived at independently

So the pattern has two independent sources of corroboration; the **N=many**
upper-bound does not. Hence the cap.

**Why 3 specifically:**

- Above 3, the human supervisor's own context budget is the bottleneck —
  the supervisor has finite context too
- API spend climbs roughly 5× while throughput climbs roughly 2× (panel E3 §6
  + PANEL-INTEGRATION dissent §2.6 in the v1.1 synthesis).
- Steve Yegge's "Merge Wall" — cross-worktree dependencies surface at merge,
  not during work — gets steeper non-linearly with N

If you have evidence the cap should be lifted **for your specific repo**
(e.g. genuinely independent module boundaries, supervisor with high working
memory), set `WT_CAP=5` and document why in your repo's CLAUDE.md. Don't
quietly raise it library-wide.

## Files

```
core/worktree-spawn/
├── commands/worktree.md                  # /worktree slash-command (Claude Code)
├── scripts/spawn.sh                      # create N worktrees + coordination files
├── scripts/cleanup.sh                    # safe removal (refuses dirty/unmerged)
├── scripts/list.sh                       # ps-style status table
├── templates/coordination-CLAUDE.md      # per-worktree CLAUDE.md template
├── templates/feature-charter.md          # per-worktree FEATURE-CHARTER.md template
├── tests/tasks.yaml                      # 2 golden tasks (cap-pass, cap-fail)
├── tests/fixtures/                       # tiny git fixture used by the tests
├── README.md                             # this file
└── CAVEAT.md                             # honest "when this is the wrong call"
```

## Install

The slash-command lives under `core/worktree-spawn/commands/worktree.md`. Either:

- **Project-scoped** (recommended): symlink from `.claude/commands/worktree.md`:
  ```sh
  mkdir -p .claude/commands
  ln -s ../../core/worktree-spawn/commands/worktree.md .claude/commands/worktree.md
  ```
- **User-scoped**: copy to `~/.claude/commands/worktree.md` (note: scripts paths
  inside the command are relative to the repo, so it still expects to run from
  inside a checkout of `claude-skills` or another repo with a similar layout —
  adjust `allowed-tools` and the script paths if you vendor it differently).

You may also call the scripts directly from the repo root without the slash-command:

```sh
core/worktree-spawn/scripts/spawn.sh   p0-04 2 --scope "build worktree-spawn"
core/worktree-spawn/scripts/list.sh
core/worktree-spawn/scripts/cleanup.sh wt/p0-04-1
```

## Usage

```sh
# Spawn 2 worktrees for task "auth-rewrite"
/worktree spawn auth-rewrite 2 --scope "back-end split: jwt issuer vs session store"

# What's currently in flight?
/worktree list

# Done with one of them?
/worktree cleanup wt/auth-rewrite-1

# Need to abandon work-in-progress?
/worktree cleanup wt/auth-rewrite-2 --force        # warns and removes anyway
```

## Branch + path layout

- Branch:  `wt/<task-id>-<seq>`        (override prefix via `WT_BRANCH_PREFIX`)
- Path:    `.worktrees/<task-id>-<seq>` (override root via `WT_ROOT`)
- Sequence numbers are picked by scanning existing branches that match the
  prefix, so sibling spawns never collide.

## Acceptance criteria (from roadmap §2.4)

- [x] `/worktree spawn 3` creates exactly 3 worktrees on isolated branches.
- [x] Hard refuses N > 3 with `cap reached; merge or delete one before spawning more` and exit 3.
- [x] Each worktree's `CLAUDE.md` identifies its sister worktrees (paths + branch names).
- [x] Merge-wall caveat is printed (Steve Yegge's "Merge Wall").
- [x] `cleanup.sh` removes a worktree iff its branch is merged or work is committed; refuses otherwise.
- [x] Synthetic test (see `tests/tasks.yaml`): spawning 4 fails cleanly and creates zero worktrees.

## Citation backbone

- Superpowers Phase 2 worktree skill, Anthropic-endorsed: [obra/superpowers](https://github.com/obra/superpowers); [SKILL.md](https://raw.githubusercontent.com/obra/superpowers/main/skills/using-git-worktrees/SKILL.md); [marketplace inclusion](https://github.com/anthropics/claude-plugins-official/blob/main/.claude-plugin/marketplace.json).
- "259 PRs" framing dropped per `docs/review/v1.1/CITATIONS-FIXED.md §5` (CITE-4); the figure is vendor-internal.
