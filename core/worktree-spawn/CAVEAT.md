# CAVEAT — when `worktree-spawn` is the wrong call

This skill is shipped at `P0` because the pattern is real and corroborated. That
does not make it universal. Most software work most of the time should NOT use
parallel worktrees. This file lists the places where it's wrong and the cases
where it's right, with the merge-conflict-tax curve in the middle so you can
decide.

## When 1 worktree beats N

Default to a single worktree if **any** of these hold:

1. **Small feature (≤3 files, ≤200 LoC).**
   The spawn + cleanup + sibling-coordination overhead is several minutes of
   supervisor attention; the feature itself is the same. Net negative.

2. **Single-language, single-module change.**
   No genuine independence between slices. "Split it across worktrees" then
   becomes "constantly rebase one against the other" — strictly worse than
   doing them in sequence in one worktree.

3. **You're still figuring out the design.**
   Parallel worktrees commit you to a partition. If you don't yet know what the
   partition should be, a single Plan-Mode session in one worktree is the right
   primitive — split *after* you know the boundary.

4. **Solo work without a real review loop.**
   Parallel worktrees rely on a supervisor to merge & adjudicate. If you are
   both author *and* supervisor and you only have ~1 hour of effective focus
   left, you will not in fact review N parallel streams; you'll ship one and
   abandon the others.

5. **Tight coupling on shared state (DB schema, public API, build graph).**
   Whatever speedup you get in parallel implementation is paid back as merge
   conflicts. Often more than paid back.

6. **You haven't already shipped one feature in this repo using a single
   worktree.** Walk before running. If you don't yet know the verify command,
   the lint quirks, and the test-flakiness profile of the repo, splitting
   across worktrees multiplies friction.

7. **No `make verify` / `npm test` / `pytest` equivalent that exits 0/non-0.**
   Without a deterministic green/red signal, parallel worktrees don't have a
   merge gate — and "I tested it locally" doesn't survive the merge wall.

## When N worktrees beat 1

Reach for `/worktree spawn` only if **at least 2** of these hold:

1. **Genuinely independent slices.** Backend + frontend; two unrelated bug fixes;
   spec exploration spike vs. implementation. The slices share a parent commit
   and very little else.

2. **Each slice has its own verify command** (or the same one, but the slices
   touch disjoint files).

3. **Supervisor bandwidth is the bottleneck, not implementation.**
   You are personally fast at reviewing & merging but slow at typing — parallel
   agents can fill the gap. If you're slow at reviewing, parallelism makes that
   worse.

4. **The repo has a stable mainline.** You can rebase one branch on another
   without random sibling rebases breaking everything.

5. **You expect the slices to merge in <1 day each.**
   Long-lived parallel branches always pay the merge wall — the cost compounds
   with branch age.

## The merge-conflict tax curve (rough)

```
   merge cost
       ^
       |                                        *
       |                                  *
       |                            *
       |                       *
       |                   *
       |                *
       |             *
       |          *
       |        *
       |      *
       |     *
       |   *
       |  *
       | *  ← N=2 (small): ~10–20 min of rebase
       |*
       +----+----+----+----+----+----+----+--->
       1    2    3    4    5    6    7    N
```

Numbers from internal estimates + community reports
The cap of 3 is empirical, not optimal — at N=4 the supervisor's own context
budget collapses before the merge wall is even reached.

The curve is **per-task** and **non-linear in N**. Three short-lived (<1d)
branches on a clean repo are roughly tractable. Three long-lived branches on
a hot-spotty repo are not.

## When *neither* is right (consider sub-agents instead)

- **Audit / review / cross-cutting reads.** Use `audit` (P0-02) / `delta-code-review`
  (P0-05) sub-agents in the *same* worktree. Audits don't need a branch.
- **Pure exploration.** A single Plan-Mode session beats N parallel agents that
  are all just reading the codebase. There is no merge to do.

## Cap override

The hard cap is a default, not a constitution. To raise it for *your specific
repo*:

```sh
WT_CAP=5 ./scripts/spawn.sh ...
```

…**and** add to your repo's CLAUDE.md:

> Cap raised to 5 because: (your reason). Reviewer: (your name). Date: (today).
> Promotion trigger if this turns out to be wrong: (the failure mode you'll
> watch for).

Don't raise the cap library-wide. The library default is the conservative one,
and that's deliberate.

## Anti-patterns this skill does NOT solve

- **Sub-agent fan-out without parent supervision.** Spawning sub-agents from
  inside a worktree without a human in the loop replaces the merge wall with
  silent drift. Out of scope here.
- **Multi-model orchestration.** Routing different worktrees to different
  models (Haiku for one, Opus for another) is `claude-code-router` territory,
- **Auto-merge on green.** `cleanup.sh` requires the human to approve removal.
  Auto-merging green branches is a CI choice, not a worktree-spawn choice.

## Parallel-by-default decision

Does workstream B depend on A's output? If yes → sequential.
If no → parallel up to cap-3.
