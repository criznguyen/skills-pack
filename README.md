# skills-pack

Version: see [`VERSION`](VERSION) · matches the upstream `claude-skills` release tag (current: `v1.6.0`).

A drop-in pack of [Claude Code](https://claude.com/claude-code) skills, hooks, and slash commands that turn the agent into a disciplined senior engineer — **type-checked tool surface, sandboxed by default, audit-gated, force-push-blocked, credential-refusing, loop-circuit-broken, postcondition-verified**.

Designed for solo operators and small teams who want guardrails without building a framework. Everything is plain `SKILL.md` + bash hooks; nothing is hidden behind a runtime.

---

## What you get

### Hooks (always-on after install)

| Skill | What it does |
|---|---|
| **`core-config`** | Loads task-class rubric (trivial / small / feature / system-change) + idea-evaluation pointer into every session. 6 hooks: anti-fantasy, blast-radius, pre-audit-gate, block-destructive (Bash blacklist: `rm -rf /`, `mkfs`, `dd` to raw disk, fork bomb…), pre-edit-stash (insurance `git stash` before every Edit/Write/MultiEdit so you can recover), and lint-touched (per-project `ruff` / `eslint` / `rustfmt` / `shellcheck` / `jq` on touched files; shadow-mode default, opt-in blocking via `LINT_TOUCHED_BLOCKING=1`; project-scoped via `--project`). |
| **`governance-pack`** | Bundles all guard hooks below. Blocks writes to denylisted prod paths, strips `Co-Authored-By:` trailers from commit messages, gates audits, warns on un-cleared `[DEBUG-<hex>]` tags pre-commit, emits JSONL telemetry. |
| **`postcondition-hook`** | After `Bash`/`Edit`/`Write`/`MultiEdit`/`NotebookEdit`, walks `~/.claude/postconditions.d/*.sh` and asserts the world matches the agent's claim. Shadow-mode by default; promote to blocking after measuring false-positive rate. |
| **`quarantine-pack`** | After `mcp__.*`/`WebFetch`/`Read`, prepends `[QUARANTINE-NOTICE: ...]` so untrusted external content is treated as data, not directives. Trusted-MCP allowlist at `~/.claude/quarantine.d/trusted-mcp-allowlist.txt`. |
| **`git-force-push-gate`** | Hard-blocks `git push --force` / `--force-with-lease` and `git commit --no-verify` / `git push --no-verify` on protected branches (default: `main`, `master`, `release/*`, `production`). Per-branch bypass via marker file or env var. |
| **`hardcoded-credential-refusal`** | Hard-blocks `Edit`/`Write`/`MultiEdit` containing AWS / GitHub / Stripe / OpenAI / Slack / JWT / RSA-private-key patterns unless a `// gitleaks:allow` marker sits within ±3 lines. |
| **`file-write-stale-stat-refusal`** | Caches mtime on every `Read`; refuses subsequent `Edit`/`Write`/`MultiEdit` if the file changed under us. Forces a re-read instead of clobbering concurrent edits. |
| **`loop-circuit-breaker`** | Three per-session counters: `iteration_count` (cap 150), `usd_spent` (per Anthropic price table), `hash_collisions` (3 in rolling 10-call window). Halts on any breach with stderr + JSONL telemetry. Per-call bypass via `LOOP_BREAKER_BYPASS_TOKEN`. |
| **`typed-tool-surface`** | Validates `tool_input` against the per-skill JSON Schema declared in SKILL.md frontmatter (`blast_radius:` ∈ {read-only, local-write, repo-write, network-write, external-side-effect}, `args_schema:` ref). Advisory by default; flip to blocking per-skill. |

### Opt-in flags

| Skill | What it does |
|---|---|
| **`sandbox-default-on`** | Flips `permissions.defaultMode: "sandbox"` in `~/.claude/settings.json`. Per-skill opt-out via SKILL.md `sandbox_required: false`. Run with `--enable-sandbox` only. |
| **`recovery-class-fragment`** | Stages a TSV-driven hint emitter (`[RECOVERY-HINT: class=<class> action=<primitive>]`) but doesn't register a matcher. Operator wires PostToolUse themselves. |
| **`eval-contamination-probe`** | Template for adding `PROBE-<sha8>-<feature>-<idx>` IDs + `assert: not-contains` against literal `${PROBE_ID}_REFERENCE_SOLUTION:` to your own promptfoo golden tasks. |

### Slash-command primitives

| Skill | How to invoke |
|---|---|
| **`audit`** | Say *"audit this branch"* / *"security review"* — triggers automatically. Output lands in `docs/sdlc/audit/<id>-{findings.json,audit-report.md}`. AI-provenance footer, fixed glossary, verdict enum `{PASS, BLOCK, ESCALATED}`. |
| **`delta-code-review`** | Say *"review this diff"* — picks up `git diff --cached`. Output: `docs/sdlc/delta-code-review/<REVIEW-NNN>.md` (lazy emission — skipped on clean PRs). Embeds Karpathy's match-style + every-line-traces + dead-code-call-out rules. |
| **`worktree-spawn`** | `/worktree spawn <feature-name>` — creates an isolated git worktree for parallel work. Capped at 3 active worktrees. |

### UX conventions (auto-attaching docs skills)

| Skill | When it triggers |
|---|---|
| **`anti-ai-ux`** *(v1.5.0+)* | Auto-attaches when generating UI for an AI-driven product (project imports `react`/`vue`/`svelte`/`flutter`/SwiftUI **AND** the prompt mentions chatbot / agent / Claude / copilot / etc.). Codifies five patterns — real-time progress, visible rollback, explain reasoning, consent before destructive, show data flow — with React, Vue 3, Svelte 5, Flutter, and SwiftUI examples per principle. Read-only skill, no hooks. |

### Opinions (review before adopting)

- `opinions/model-routing/` — cost-quality routing rubric + `lock-opus` / `post-tool-use-failure` / `subagent-stop` / `user-prompt-submit` / `diff-size-tripwire` hooks. Personal defaults; rollback recipes included.

---

## Requirements

- [Claude Code](https://claude.com/claude-code) ≥ 2.0
- `bash`, `jq`, `git`
- Optional: `npx` + Node ≥ 22 if you want to run promptfoo against per-skill tasks

---

## Install

```bash
git clone https://github.com/criznguyen/skills-pack.git ~/src/skills-pack
cd ~/src/skills-pack

# 1. CLAUDE.md task-class rubric + 5 user-scope hooks (lint-touched is opt-in project-scope, see --project below)
./core/core-config/install.sh

# (optional) Also install lint-touched.sh into <repo>/.claude/hooks/ — runs ruff/eslint/rustfmt/shellcheck/jq on touched files (shadow-mode by default).
# ./core/core-config/install.sh --project /path/to/repo

# 2. All hook bundles (postconditions + quarantine + 8 v2.0-wave hooks)
./core/governance-pack/install.sh
```

Both installers are **idempotent**, **dry-run-able** (`--dry-run`), and write a **timestamped backup** before merging into existing config.

### Scopes

```bash
# User scope (default) — applies to every project on this machine
./core/core-config/install.sh
./core/governance-pack/install.sh

# Project scope — applies to one repo only
TARGET=/path/to/repo/.claude ./core/core-config/install.sh
./core/governance-pack/install.sh --project /path/to/repo

# Non-interactive (CI / scripted)
./core/governance-pack/install.sh --force
```

### Per-feature toggles

`governance-pack/install.sh` composes every hook above. Each step is independently gateable:

| Flag | Effect |
|---|---|
| `--postconditions-mode={shadow,blocking}` | Default `shadow`. Promote to `blocking` only after measuring your false-positive rate. |
| `--quarantine-only` | Re-seed quarantine config without touching other hooks. |
| `--no-quarantine` | Skip the quarantine PostToolUse hook. |
| `--no-recovery-class` | Skip recovery-class staging. |
| `--no-git-push-gate` | Skip the force-push / no-verify gate. |
| `--no-cred-refusal` | Skip the credential-regex scan on file writes. |
| `--no-stale-stat` | Skip the stale-mtime gate on file writes. |
| `--no-loop-cb` | Skip loop-circuit-breaker. |
| `--no-typed-tool-surface` | Skip the JSON-Schema tool-input validator. |
| `--enable-sandbox` | **Opt-in.** Flip `permissions.defaultMode: "sandbox"`. |

### Slash-command primitives (audit / delta-code-review / worktree-spawn)

These are pure `SKILL.md` files with no install side effects. Symlink them so `git pull` picks up updates:

```bash
mkdir -p ~/.claude/skills
ln -s "$(pwd)/core/audit"             ~/.claude/skills/audit
ln -s "$(pwd)/core/delta-code-review" ~/.claude/skills/delta-code-review
ln -s "$(pwd)/core/worktree-spawn"    ~/.claude/skills/worktree-spawn
ln -s "$(pwd)/core/anti-ai-ux"        ~/.claude/skills/anti-ai-ux
```

### Opinions (optional)

```bash
cat opinions/model-routing/INSTALL-CLAUDE-MD.md
cat opinions/model-routing/INSTALL-HOOKS.md
# Rollback any time:
cat opinions/model-routing/ROLLBACK.md
cat opinions/model-routing/ROLLBACK-HOOKS.md
```

---

## Verify

```bash
ls ~/.claude/hooks/
ls ~/.claude/skills/
head -20 ~/.claude/CLAUDE.md
```

Each skill's own `README.md` and `SKILL.md` document its hook script paths, config files, and bypass envvars in detail.

---

## Update

```bash
cd ~/src/skills-pack
git pull
# Symlinked skills pick up updates automatically.
# For installer-driven hooks, re-run (idempotent — only diffs apply):
./core/core-config/install.sh
./core/governance-pack/install.sh
./core/governance-pack/install.sh --refresh-prompts   # re-sync core/audit/prompts/* into install dest
```

---

## Uninstall

```bash
./core/governance-pack/uninstall.sh
rm -rf ~/.claude/skills/{audit,delta-code-review,worktree-spawn,anti-ai-ux}
# core-config CLAUDE.md merge: restore from the timestamped backup
ls ~/.claude/CLAUDE.md.bak.*
```

---

## Design rationale

The pack defends against five recurring failure modes — sidetrack, scope creep, fantasy approval, context loss, skipped review — without building yet another framework. Everything is a primitive: `SKILL.md`, hook script, settings bundle, CLAUDE.md fragment.

Full charter: [`docs/synthesis/v1.1/charter-v1.1.md`](docs/synthesis/v1.1/charter-v1.1.md).

---

## Recent versions

Full history in [`CHANGELOG.md`](CHANGELOG.md).

- **`v1.6.0`** (2026-05-04) — new `core/fix-root-cause/` skill: 4-question workaround gate + 12 anti-patterns + standard `// WORKAROUND:` comment template. Codifies the "fix root cause, no workaround" rule — agent must answer YES to all 4 questions (documented time pressure / comment-tagged in source / follow-up tracked with owner+deadline / reversibility plan documented) before any workaround ships. Pairs with `core-config` (anti-fantasy sibling), `audit` (catalog feeds PE-dimension checklist), `delta-code-review` (catches suppressed errors). Pure additive: new directory, no hooks, no `settings.json` edits.
- **`v1.5.0`** (2026-05-04) — new `core/anti-ai-ux/` skill: five UX patterns (real-time progress, visible rollback, explain reasoning, consent before destructive, show data flow) the agent applies by default when generating user-facing UI for agent-driven products. Auto-attaches when both a UI-framework signal (React/Vue 3/Svelte 5/Flutter/SwiftUI) AND an AI-product signal are present. Pure additive: new directory, no hook changes, no `settings.json` edits.
- **`v1.4.4`** (2026-05-03) — hotfix triple. `deny-prod-paths.sh` jq probe now runs `jq --version` so a broken jq symlink in PATH no longer silently bypasses the denylist (+1 test). `block-destructive.sh` adds a doc-context whitelist so `git commit -m "block rm -rf /"` and `echo`/`cat`/heredoc bodies no longer trip on their own description text — chained commands (`&&`/`;`/`|`/`||`) still scan (+5 tests). Allowlist docs gain "Pattern format" RIGHT vs WRONG examples — patterns must prefix `**/` because they match against absolute paths.
- **`v1.4.3`** (2026-05-03) — `governance-pack` per-project allowlist. Drop `<project_root>/.claude/governance-allow.txt` (same glob format as `prod-paths.txt`) and listed paths win over the universal denylist FOR THAT PROJECT ONLY, with a JSONL audit trail at `.claude/state/governance-allow.jsonl`. Use it for surge work in protected paths (audit-remediation on `internal/auth/`, schema-redo across `db/migrations/`, billing refactor); remove the file when done. Projects without the file see zero behavior change. Example: `printf '**/internal/auth/**\n**/db/migrations/**\n' > .claude/governance-allow.txt` (note: patterns must start with `**/` per v1.4.4 docs). See [`core/governance-pack/README.md`](core/governance-pack/README.md) §"Per-project allowlist (v1.4.3+)".
- **`v1.4.2.1`** (2026-05-03) — `pre-edit-stash` hotfix: no longer reverts the worktree on sequential edits. The previous primitive moved the targeted file's uncommitted changes off the worktree before each Edit/Write, silently reverting multi-step refactors between tool calls. Replaced with `git stash create` + `git stash store`, which snapshots the worktree without touching it. The `git stash list` recovery contract is preserved.
- **`v1.4.2`** (2026-05-03) — `core/core-config/` ships the 3 hooks the README and `governance-pack` template have been referencing: `block-destructive.sh` (catastrophic-shell blacklist), `pre-edit-stash.sh` (insurance stash before every Edit/Write), `lint-touched.sh` (per-project `ruff` / `eslint` / `rustfmt` / `shellcheck` / `jq` on touched files, shadow-mode default).

---

## License

[Apache-2.0](LICENSE). Third-party attribution: [`NOTICES.md`](NOTICES.md).
