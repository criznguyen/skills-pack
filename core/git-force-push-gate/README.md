# `git-force-push-gate` — PreToolUse hook refusing force-push, --no-verify, and pre-commit→commit-msg rename evasion

v2.0 P1 #1 (v2.1 argv-parse fix — flags must be argv tokens, not bytes inside a quoted message). v1.7.0 hook-rename evasion detection. Charter §2.2 hooks-over-rules.

> **Why a hook, not a CLAUDE.md rule.** The Replit `DROP TABLE` (July 2025) and Cursor PocketOS (April 2026) incidents both happened because the safety boundary was a system-prompt instruction, not a `PreToolUse` block. An instruction-injected agent will follow the injection; a hook with `exit 2` will not.

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body. |
| `CLAUDE.md` | Agent-facing fragment ("if user asks to bypass force-push refusal, do not auto-bypass — surface the bypass mechanism to the operator"). |
| `hooks/git-push-gate.sh` | PreToolUse(`Bash`). Tokenizes `tool_input.command` (v2.1 argv-aware via `python3 shlex` with bash `eval set --` fallback) and inspects each `git push` / `git commit` invocation's argv tokens for `--force`, `--force-with-lease`, `-f`, `--no-verify`. v1.7.0 also detects `pre-commit→commit-msg` rename evasion via `mv`/`cp`/`install`/`ln`/`git mv` chunks. Substring-in-message bytes (e.g. `git commit -m "fix --no-verify path"`) are ignored. On flag match + protected branch + no bypass → exit 2. |
| `templates/protected-branches.txt` | Default protected list: `main`, `master`, `release/*`, `production`. |
| `tests/test-git-push-gate.sh` | 17-case unit suite: 8 baseline (allow/refuse/bypass × force-push/no-verify × protected/unprotected) + 4 v2.1 argv-parse regressions (literal flag chars in commit message body must not trip the gate) + 5 v1.7.0 hook-rename detection (mv/cp/git-mv variants, message-body literal, legitimate backup, .bak rename). |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |
| `examples/sample-output.jsonl` | 3-line synthetic JSONL sample (privacy-clean). |

## What gets blocked

| Command pattern | Branch | Decision |
|---|---|---|
| `git push --force ...` | protected | refuse (exit 2) |
| `git push -f ...` | protected | refuse (exit 2) |
| `git push --force-with-lease ...` | protected | refuse (exit 2) |
| `git commit --no-verify ...` | any | refuse (exit 2) |
| `git push --no-verify ...` | any | refuse (exit 2) |
| `git push --force feat/personal-branch` | unprotected | allow |
| `git push origin main` (no `--force`) | protected | allow |
| `mv .git/hooks/pre-commit .git/hooks/commit-msg` (and cp/install/ln/git-mv variants) | any | refuse (exit 2) — v1.7.0 |
| `git mv .git/hooks/pre-commit .git/hooks/commit-msg` | any | refuse (exit 2) — v1.7.0 |
| `cp .git/hooks/pre-commit /tmp/backup` | any | allow (no commit-msg in same chunk) |
| `git commit -m "rename pre-commit to commit-msg in docs"` | any | allow (literal in message body) |

Branch resolution: the hook runs `git symbolic-ref --short HEAD` from the cwd of the Bash call; if the result matches any pattern in `~/.claude/git-force-push-gate/protected-branches.txt` (literal or glob), the branch is protected.

## Bypass mechanisms

In order of preference (ergonomically and security-wise):

1. **Per-branch marker file** — `touch ~/.claude/git-force-push-gate-allow/main` allows force-push to `main` for the duration the file exists. Operator deletes the marker when done.
2. **Per-session bypass token** — `export GIT_FORCE_PUSH_BYPASS_TOKEN=$(cat ~/.claude/git-force-push-gate/bypass-token.sha)`. The token must match the SHA in `~/.claude/git-force-push-gate/bypass-token.sha` exactly. Default install does NOT seed the token; operators opt in.
3. **Per-session disable** — `export GIT_FORCE_PUSH_GATE_DISABLE=1` silences the hook entirely. Use for emergency rollback only.

## Install

```bash
bash core/governance-pack/install.sh        # Step 11 wires git-force-push-gate
bash core/governance-pack/install.sh --dry-run
```

The installer:

1. Copies `hooks/git-push-gate.sh` to `~/.claude/hooks/git-force-push-gate/`.
2. Seeds `~/.claude/git-force-push-gate/protected-branches.txt` from the template (preserves operator edits unless `POSTCONDITIONS_FORCE=1`).
3. Creates `~/.claude/git-force-push-gate-allow/` (empty marker dir).
4. Registers the `PreToolUse(Bash)` matcher in `~/.claude/settings.json`.

## Uninstall

```bash
bash core/governance-pack/uninstall.sh                  # removes hook + de-registers
rm -rf ~/.claude/git-force-push-gate                    # operator data
rm -rf ~/.claude/git-force-push-gate-allow              # operator markers
```

## Forbidden in hook bodies (TM4)

`hooks/git-push-gate.sh` is shell + grep + jq + python3-fallback only. No LLM invocation, no sub-agent. CI step `git-force-push-gate-integrity-check` re-runs the TM4 grep on every push.

## Performance budget

| Metric | Target |
|---|---|
| Median per-call latency (Bash with no force-push) | ≤ 5 ms |
| Median per-call latency (force-push + branch lookup) | ≤ 30 ms |
| Hard timeout | 5000 ms |

## References

- Final report v2.0 plan: [`docs/research/harness-skills-required/00-final-report.md`](../../docs/research/harness-skills-required/00-final-report.md) §5 P1 #1
- Charter §2.2 hooks-over-rules: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
- Precedent shape: [`core/governance-pack/hooks/no-coauthor-trailer.sh`](../governance-pack/hooks/no-coauthor-trailer.sh) (PreToolUse(Bash) parser)
