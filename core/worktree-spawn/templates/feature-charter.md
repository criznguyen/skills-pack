# Feature charter — {{TASK_ID}} / worktree {{WORKTREE_N}} of {{WORKTREE_TOTAL}}

> Branch: `{{BRANCH}}` · Path: `{{WORKTREE_PATH}}` · Spawned: {{SPAWN_TS}}

This charter is what each Claude session in this worktree should read **first**, after the per-worktree `CLAUDE.md`.
Fill in the four sections below before starting implementation. An empty charter == an unfocused agent.

---

## 1. Problem statement

(One paragraph. What is being built/fixed/refactored. Why now. What was already tried.)

Initial scope hint from spawn:
> {{SCOPE}}

## 2. Success criteria (≥1 measurable)

(Boxes the user checks to call this done. Each must be measurable — "feels good" does not count.)

- [ ] …
- [ ] …
- [ ] Verify command exits 0: `make verify`  (or repo equivalent)

## 3. Non-goals

(Things explicitly out of scope. Prevents creep, especially when sibling worktrees are tempted to "help".)

- …
- …

## 4. Verification command

(The single command this worktree's "done" is measured by. No verification command == no done.)

```sh
# example
make verify
```

---

## Sibling boundary

This worktree is one of {{WORKTREE_TOTAL}}. Sibling worktrees are working on:

{{SIBLINGS}}

If you discover that completing this charter requires reaching into a sibling's scope, **stop and write it into `BLOCKERS.md`**. The supervisor — not an agent in this worktree — decides whether to widen the scope, redraw the boundary, or merge first.

## Merge order assumption

{{MERGE_ORDER}}

If your work invalidates this order (e.g. you discover a hard dependency on a
later-merging sibling), surface it explicitly instead of silently rebasing.
