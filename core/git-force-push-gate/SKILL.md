---
name: git-force-push-gate
description: PreToolUse hook (matcher Bash) refusing `git push --force` / `--force-with-lease` and `git commit --no-verify` / `git push --no-verify` on protected branches (`main`, `master`, `release/*`, `production`). Hard-block exit 2 with stderr advisory; bypass only via per-branch marker file `~/.claude/git-force-push-gate-allow/<branch>` or `GIT_FORCE_PUSH_BYPASS_TOKEN` env-var. v2.0 P1 #1.
type: governance
tools: Bash, Read, Grep
model: opus
blast_radius: external-side-effect
last-validated: 2026-04-29
---

# git-force-push-gate

Charter §2.2 hooks-over-rules. The Replit `DROP TABLE` and Cursor PocketOS incidents proved that prose like *"don't force-push to main"* in CLAUDE.md is unreliable; an instruction-injected agent will follow the injection. A `PreToolUse(Bash)` hook with `exit 2` is the deterministic enforcement.

## When to use

Auto-installed by `core/governance-pack/install.sh` Step 11. Operators who run sessions with shell access to a git working tree are protected against:

- `git push --force <remote> <branch>` where `<branch>` matches the protected list.
- `git push --force-with-lease ...` on protected branches.
- `git commit --no-verify ...` (any branch — `--no-verify` skips pre-commit hooks, which is itself the abuse).
- `git push --no-verify ...` (any branch).

The default protected list lives in `~/.claude/git-force-push-gate/protected-branches.txt`:

```
main
master
release/*
production
```

The hook reads the file every invocation; operator edits take effect immediately.

## When NOT to use

- **For force-pushing a personal feature branch.** That is the legitimate use case. The hook lets `git push --force feat/my-branch` through unchanged.
- **For the rebase workflow on long-lived feature branches.** Same answer — feature branches are not in the protected list.
- **For squash-and-merge from a PR UI.** The hook only fires on `Bash` tool calls; GitHub/GitLab UI merges do not invoke `Bash`.

## Bypass mechanisms (in order of preference)

1. **Per-branch allow marker** — `touch ~/.claude/git-force-push-gate-allow/<branch>` (file presence allows force-push to that branch for the session). The marker file is operator-created, not hook-created — there is no auto-create code path.
2. **Per-session bypass token** — `export GIT_FORCE_PUSH_BYPASS_TOKEN=<sha>`. The hook verifies token matches the SHA-pin in `~/.claude/git-force-push-gate/bypass-token.sha` (operator seeds this once at install time).
3. **Per-session disable** — `export GIT_FORCE_PUSH_GATE_DISABLE=1` silences the hook entirely.

The default install does NOT seed `bypass-token.sha`, so option 2 is unavailable until the operator opts in.

## Parse semantics (v2.1)

`hooks/git-push-gate.sh` tokenizes `tool_input.command` via `python3 shlex.split` (preferred) or a bash `eval set --` fallback gated by a `bash -n` syntax check. Only flags that arrive as their own argv tokens are matched — `--no-verify` or `--force` appearing as bytes inside a quoted commit-message body (e.g. `git commit -m "fix --no-verify path"`) is ignored. Shell-meta operators (`;`, `&&`, `||`, `|`) split the token stream so each `git` invocation is inspected in isolation.

## Forbidden in hook bodies (TM4)

`hooks/git-push-gate.sh` is shell + grep + jq + python3-fallback only. No LLM invocation, no sub-agent. Enforced by `tests/test-no-claude-spawn.sh`.

## Telemetry

One JSONL line per fired hook invocation to `~/.claude/telemetry.jsonl`:

```json
{"event":"git-push-gate","ts":"...","tool":"Bash","decision":"refused|allowed|bypass","branch":"main","reason":"force_push|no_verify","session_id":"..."}
```

Privacy invariant: no `tool_input.command` body is persisted, only the resolved decision + branch name (which is not sensitive — the branch name is a public git ref).

## Install / Uninstall

Wired by `core/governance-pack/install.sh` Step 11. Three-command uninstall:

```bash
bash core/governance-pack/uninstall.sh   # removes hook + de-registers
rm -rf ~/.claude/git-force-push-gate ~/.claude/git-force-push-gate-allow
```

## References

- Charter §2.2 hooks-over-rules: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
- Replit DROP TABLE incident: <https://fortune.com/2025/07/23/ai-coding-tool-replit-wiped-database>
- Cursor PocketOS incident: <https://www.theregister.com/2026/04/27/cursoropus_agent_snuffs_out_pocketos/>
