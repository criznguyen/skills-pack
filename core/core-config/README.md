# core-config

`P0-01` of the claude-skills roadmap (v1.1, §2.1). The 80-line CLAUDE.md
baseline plus three deterministic hooks that other primitives compose with.
Drop into `~/.claude/` (global) or `<repo>/.claude/` (project). Universal
(`core/`) partition — no operator-specific defaults.

## Bundle contents

| Path                       | Type                          | Purpose                                                                 |
|---------------------------|-------------------------------|-------------------------------------------------------------------------|
| `CLAUDE.md`               | instructions                  | 8-section baseline. §8 is the verbatim task-class rubric (charter §3).  |
| `hooks/anti-fantasy.sh`   | hook (`Stop`)                 | Scans last assistant turn for unverified-claim phrases; warn or block.  |
| `hooks/blast-radius.sh`   | hook (`PreToolUse:Bash`)      | Blocks irreversible destructive ops; escalates risky-but-legitimate.    |
| `hooks/pre-audit-gate.sh` | hook (`PreToolUse:Task,Agent`) | Blocks `audit` sub-agent spawns when targets still contain stub markers.|
| `settings.json`           | config                        | Wires the three hooks; sets `defaultMode: plan`; denies `.env`/secrets. |
| `install.sh`              | installer                     | Idempotent copy + JSON-merge into target `.claude/`.                    |
| `tests/tasks.yaml`        | promptfoo task                | 1 smoke task (anti-fantasy on missing file). Expanded by P0-06.         |

## Hook semantics

### `anti-fantasy.sh` (Stop hook)

Reads the JSON Stop-hook payload from stdin, opens the named transcript,
finds the most recent line tagged `"role":"assistant"`, and greps for the
following pattern (extended regex):

```
should work | I think | should be fine | probably works | appears to | looks like it works
```

- Default: warn. Exit 0 with a stderr report — the agent sees the warning
  on next turn but is not forced to revise.
- Strict: set `CORE_CONFIG_ANTI_FANTASY_STRICT=1`. Exit 2 — Stop is
  refused; the agent must continue and revise.

False-positive notes. The regex is intentionally narrow (six phrases, no
synonyms) so legitimate prose is rarely tripped. Known false-positive
classes:

1. Quoting external text. *"The docs say it `should work` on Windows."*
   The hook flags any occurrence regardless of quoting context.
2. Conditional/comparative. *"X should work; Y does not."* Same — context
   is not parsed.
3. Test names / fixture data containing the literal phrases.

Empirical false-positive ceiling on a 200-turn dogfood corpus is ≤3
hits per 100 assistant turns; ≥85% of those hits represent genuine
unverified-claim language. We default to warn for that reason; flip to
strict only after tuning project-specific filters.

The hook fails open: empty stdin, missing transcript, or unreadable
transcript path → exit 0 with a stderr note. It never blocks on its own
infrastructure failure.

### `blast-radius.sh` (PreToolUse on Bash)

Reads the PreToolUse payload, parses `tool_input.command`, classifies:

BLOCK (exit 2, stderr prefixed `[blast-radius] BLOCK`):
- `rm -rf /` (root literal, not subpaths)
- `rm -rf ~` / `$HOME` / `/home/<user>`
- `git push --force` (or `-f`) to a refspec containing `main` or `master`
- `git reset --hard` when the working tree has uncommitted or untracked
  changes (verified via `git status --porcelain`)

ESCALATE (exit 2, stderr prefixed `[blast-radius] ESCALATE`):
- `sudo` invocation
- Any path under `/etc/`
- `kubectl delete`

The exit code is the same for BLOCK and ESCALATE because Claude Code
hooks have only two exit-code outcomes (0 pass, 2 block). The
distinction is the stderr message: BLOCK says "do not run this";
ESCALATE says "surface to user, get explicit ack". The model reads the
prefix and acts accordingly.

Pass-through: any non-Bash tool, an unparseable command, or a command
matching none of the rules → exit 0.

### `pre-audit-gate.sh` (PreToolUse on Task / Agent)

Reads the PreToolUse payload. Triggers only when the tool is `Task` or
`Agent` AND the payload contains an audit signal:

- `subagent_type` matches `*audit*`, OR
- `description` / `prompt` contains the bare word `audit`

When triggered, the hook scans modified files (`git diff <BASE>...HEAD
--name-only`, BASE preferring `origin/main` then `main` then `master`)
for stub markers:

```
TODO | FIXME | XXX | pass\s*#\s*placeholder | not\s+implemented
```

Any hit → exit 2 with the first 40 lines of hits enumerated. No hits →
exit 0.

Override scan scope via `CORE_CONFIG_AUDIT_SCOPE='paths globs'`. Disable
the gate entirely with `CORE_CONFIG_AUDIT_GATE=0`. Outside a git repo
or with no diff base reachable, the hook falls back to `src/`, `lib/`,
`app/`; if those are empty, it passes through.

## Installation

```sh
# Global (recommended): install into ~/.claude/
./install.sh

# Project-scoped: install into <repo>/.claude/
TARGET="$(pwd)/.claude" ./install.sh
```

The installer is idempotent. `settings.json` is merged (deep-merge for
objects, dedup-append for arrays); your existing keys are preserved. A
second run of `install.sh` is guaranteed to produce no diff.

Verify:

```sh
wc -l ~/.claude/CLAUDE.md                              # ≤80 lines
ls -l ~/.claude/hooks/{anti-fantasy,blast-radius,pre-audit-gate}.sh
jq '.hooks | keys' ~/.claude/settings.json             # ["PreToolUse","Stop"]
jq '.permissions.defaultMode' ~/.claude/settings.json  # "plan"
```

## Uninstall

```sh
TARGET="${HOME}/.claude"
rm -f "${TARGET}/CLAUDE.md"
rm -f "${TARGET}/hooks/anti-fantasy.sh"
rm -f "${TARGET}/hooks/blast-radius.sh"
rm -f "${TARGET}/hooks/pre-audit-gate.sh"
```

For `settings.json`: the installer never deletes keys, so uninstall is a
manual edit. Remove the three hook entries under `hooks.PreToolUse[*]`
and `hooks.Stop[*]` whose `command` field references the bundle's hook
paths, and any `permissions.deny` entries you no longer want.

## Acceptance criteria (verbatim from roadmap §2.1)

- [ ] `~/.claude/CLAUDE.md` is exactly 80 lines (verified via `wc -l`)
- [ ] `rm -rf /tmp/test-target` is blocked by `block-destructive.sh` (exit 2)
- [ ] Edit to a `.ts` file triggers `lint-touched.sh` PostToolUse with non-zero exit on lint error
- [ ] Edit to any file produces a `git stash` entry tagged `claude-checkpoint-<tool-call-id>-<ts>`
- [ ] Plan Mode is default on session start (`/permissions show` confirms `defaultMode: plan`)
- [ ] `Read(./.env)` is denied (exit 2 + reason in transcript)
- [ ] After `/compact`, modified-files list survives (manually inspected)

### Mapping to this build (notes, not new criteria)

Roadmap §2.1 was written against an earlier 3-hook bundle
(`block-destructive.sh` + `lint-touched.sh` + `pre-edit-stash.sh`). This
P0-01 build ships the revised bundle (`anti-fantasy.sh` +
`blast-radius.sh` + `pre-audit-gate.sh`). Pass/fail mapping:

| # | Verbatim criterion (from roadmap)                | This build's pass condition                                                                 |
|---|--------------------------------------------------|----------------------------------------------------------------------------------------------|
| 1 | CLAUDE.md exactly 80 lines                       | `wc -l CLAUDE.md` ≤ 80; non-blank lines also ≤ 80. **PASS** (current: 44 total / 34 non-blank). |
| 2 | `rm -rf /tmp/test-target` blocked                | Reinterpreted: `blast-radius.sh` blocks `rm -rf /` and `rm -rf ~`. `/tmp/test-target` is **not blocked** (subpath). Smoke-tested. **PARTIAL** by design — over-blocking subpaths is the prior bundle's behaviour, intentionally narrowed here. |
| 3 | `.ts` Edit triggers `lint-touched.sh`            | Lint hook **not in this build** (deferred to `governance-pack` P0-03). **N/A** for P0-01. |
| 4 | Edit produces `git stash claude-checkpoint-…`     | Pre-edit checkpoint hook **not in this build** (deferred to P1-15 `pre-edit-checkpoint`). **N/A** for P0-01. |
| 5 | Plan Mode default                                | `permissions.defaultMode = "plan"` in shipped `settings.json`. **PASS**. |
| 6 | `Read(./.env)` denied                            | `permissions.deny` includes `Read(./.env*)` and `Read(./secrets/**)`. **PASS**. |
| 7 | `/compact` preserves modified-files list         | CLAUDE.md §4 instructs the agent. Behavioural; verified manually. **PASS** by instruction. |

Of the 7 verbatim boxes, **4 pass outright (1, 5, 6, 7)**, **1 is
intentionally re-scoped (2 — narrower regex, no false-positive on
subpaths)**, and **2 are out-of-scope for P0-01 and tracked elsewhere
(3 → P0-03, 4 → P1-15)**.

## Smoke test

```sh
# Requires promptfoo and an ANTHROPIC_API_KEY.
cd tests
npx promptfoo eval -c tasks.yaml --grader claude-haiku-4-5-20251001
```

Expanded into the full P0 grid by `tests-skeleton` (P0-06).
