# `governance-pack` — settings template for hook-enforced safety

P0-03 of `claude-skills` v1.1. A paste-ready `~/.claude/settings.json` template plus four hook scripts that wire enterprise-grade safety nets on top of vanilla Claude Code. Composes cleanly with [`core-config`](../core-config/) (P0-01).

> **Charter principle (v1.1 §2.2):** *deterministic enforcement beats prose enforcement*. Hooks `exit 2` block; system-prompt rules don't. Every primitive in this pack is a hook (or settings deny rule), never an instruction.

---

## What it ships

| File | Purpose |
|---|---|
| `templates/global-settings.json` | Drop-in for `~/.claude/settings.json`. Plan-mode default + `.env`/secrets/curl deny + `WebFetch` deny + 7-hook wiring. |
| `templates/project-settings.local.json` | Project-scoped overrides (`<repo>/.claude/settings.local.json`). Project verify-cmd + per-project allowlist. |
| `templates/prod-paths.txt` | Default path-pattern denylist read by `deny-prod-paths.sh`. Operator-tunable. |
| `templates/freeze.json` | Empty per-project freeze schema (P2-19 promotion target). |
| `hooks/audit-gate.sh` | **Stop hook.** Diff > 50 LOC ⇒ advise `/audit`. Advisory-only. |
| `hooks/deny-prod-paths.sh` | **PreToolUse(Edit/Write/MultiEdit).** Blocks Edit/Write to user-defined prod paths. Exit 2. |
| `hooks/no-coauthor-trailer.sh` | **PreToolUse(Bash).** Blocks `git commit` containing `Co-Authored-By: Claude` trailer. Preserves human co-authors. |
| `hooks/telemetry.sh` | **PostToolUse(\*).** JSONL log of every tool call to `~/.claude/telemetry.jsonl`. Local only — no network. |
| `hooks/postcondition-hook.sh` | **PostToolUse(Bash\|Edit\|Write\|MultiEdit\|NotebookEdit).** Runs operator-declared verifications from `~/.claude/postconditions.d/*.sh`. Shadow-mode default (advisory exit 0) per F2-7. See "Phase 2.1 enforcement" below. |
| `../quarantine-pack/hooks/wrap-mcp-output.sh` | **PostToolUse(mcp__.\*\|WebFetch\|Read).** Advisory-mode tool-result quarantine — appends `[QUARANTINE-NOTICE: ...]` to next-turn context for untrusted external content. Charter §2.2 sub-clause #2. See [`core/quarantine-pack/README.md`](../quarantine-pack/README.md) and "Phase 2.2 sub-clause #2 (quarantine-pack)" below. |
| `../quarantine-pack/templates/{trusted-mcp-allowlist.txt, quarantine.json, quarantine-notice.template}` | Operator-owned data + advisory-text template seeded by `install.sh` Step 9. |
| `../recovery-class-fragment/hooks/recovery-classify.sh` | **PostToolUse(Bash\|Edit\|Write).** Opt-in error-recovery classifier — emits `[RECOVERY-HINT: class=<class> action=<primitive>]` when stderr matches exactly one class in `templates/recovery-classes.tsv`. v2.0 P1 #4 (no charter touch). See [`core/recovery-class-fragment/README.md`](../recovery-class-fragment/README.md). |
| `../git-force-push-gate/hooks/git-push-gate.sh` | **PreToolUse(Bash).** Blocks `git push --force` / `--force-with-lease` and `--no-verify` on protected branches (`main`, `master`, `release/*`, `production`). v2.0 P1 #1. See [`core/git-force-push-gate/README.md`](../git-force-push-gate/README.md). |
| `../hardcoded-credential-refusal/hooks/credential-scan.sh` | **PreToolUse(Edit\|Write\|MultiEdit).** Refuses writes containing high-entropy credential patterns (AWS, GitHub PAT, Stripe sk_live, OpenAI sk-, Slack xoxb-, JWT, RSA private key) without `// gitleaks:allow` marker within ±3 lines. v2.0 P1 #2. See [`core/hardcoded-credential-refusal/README.md`](../hardcoded-credential-refusal/README.md). |
| `../file-write-stale-stat-refusal/hooks/file-stat-check.sh` | **PreToolUse(Edit\|Write\|MultiEdit).** Refuses writes when the target file's mtime drifted since the agent last Read it (companion `cache-mtime-on-read.sh` populates the cache on PostToolUse Read). v2.0 P1 #3. See [`core/file-write-stale-stat-refusal/README.md`](../file-write-stale-stat-refusal/README.md). |
| `../eval-contamination-probe/templates/probe-test.yaml` | Promptfoo case template — `assert: not-contains` on per-case `PROBE-<sha8>-<feature>-<idx>` ID. v2.0 P1 #5; charter §7 SLO list. See [`core/eval-contamination-probe/README.md`](../eval-contamination-probe/README.md). |
| `../loop-circuit-breaker/hooks/{pretooluse-count-hash,posttooluse-cost,stop-summary}.sh` | **PreToolUse(*) + PostToolUse(*) + Stop.** 3-counter session circuit-breaker (iterations, USD, hash-collisions). Background-safe bypass via `LOOP_BREAKER_BYPASS_TOKEN`. v2.0 Top-5 #3; charter §2.2 sub-clause. See [`core/loop-circuit-breaker/README.md`](../loop-circuit-breaker/README.md). |
| `../typed-tool-surface/hooks/schema-validate.sh` | **PreToolUse(*).** Reads `args_schema:` from each SKILL.md frontmatter and validates `tool_input` via jq. v2.0 Top-5 #4; charter §2.2 mechanism. See [`core/typed-tool-surface/README.md`](../typed-tool-surface/README.md). |
| `../sandbox-default-on/install-flag.sh` | `governance-pack/install.sh --enable-sandbox` flips `~/.claude/settings.json` `defaultMode: sandbox`. Per-skill opt-out via SKILL.md `sandbox_required: false`. v2.0 Top-5 #5; charter §2.2 example list + §2.4-bis tracker. See [`core/sandbox-default-on/README.md`](../sandbox-default-on/README.md). |
| `templates/postconditions.d/` | 12 default postcondition snippets — 9 functional defaults (`mkdir.sh`, `git-push.sh`, `edit-readback.sh`, `write-stat.sh`, `bash-exitcode.sh`, `mv.sh`, `rm.sh`, `npm-install.sh`, `pytest.sh`) + 3 integrity/template files (`_self.sh` Edit-matcher integrity check, `_self-write.sh` Write-matcher sibling per PC-H1 remediation, `_template.sh` skeleton for new postconditions). Operator-owned, hand-editable. |
| `templates/postconditions.json` | Mode config (`shadow` default; flip to `blocking` after 30-day FP measurement). |
| `install.sh` | Interactive installer. Merges into existing settings; never overwrites. Backs up before merging. |
| `uninstall.sh` | Reverses install.sh; offers backup restore. |
| `EXAMPLES.md` | Before/after diffs of `settings.json` for the 4 most common starting states. |
| `tests/tasks.yaml` | One Promptfoo task: planted commit-with-coauthor; assert hook strips. |

---

## Install

```bash
# Global only (~/.claude/)
./install.sh

# Global + project (run from repo root)
./install.sh --project

# Preview without modifying anything
./install.sh --dry-run
```

The installer:
1. Copies `hooks/*.sh` to `~/.claude/hooks/governance-pack/`.
2. Writes `~/.claude/prod-paths.txt` if absent (default denylist).
3. **Asks before merging** into an existing `~/.claude/settings.json`. Backs up to `settings.json.bak.YYYYMMDD-HHMMSS`.
4. With `--project`: drops `.claude/settings.local.json` + `.claude/freeze.json` into the current repo.

To roll back: `./uninstall.sh` (offers to restore the most recent backup).

---

## Compose with `core-config` (P0-01)

`core-config` ships **3 hooks**; `governance-pack` adds **4 enterprise extras**. They layer in the same matchers without conflict because each hook does ONE thing and exits 0/2 cleanly.

| Event | Matcher | Hook | Source | Order |
|---|---|---|---|---|
| `PreToolUse` | `Bash` | `block-destructive.sh` | core-config | 1 |
| `PreToolUse` | `Bash` | `no-coauthor-trailer.sh` | governance-pack | 2 |
| `PreToolUse` | `Edit\|Write\|MultiEdit` | `pre-edit-stash.sh` | core-config | 1 |
| `PreToolUse` | `Edit\|Write\|MultiEdit` | `deny-prod-paths.sh` | governance-pack | 2 |
| `PostToolUse` | `Edit\|Write\|MultiEdit` | `lint-touched.sh` | core-config | 1 |
| `PostToolUse` | `.*` | `telemetry.sh` | governance-pack | 2 |
| `PostToolUse` | `mcp__.*\|WebFetch\|Read` | `wrap-mcp-output.sh` | quarantine-pack | dedicated arm |
| `Stop` | `.*` | `audit-gate.sh` | governance-pack | 1 |

**Order matters only when one hook would obsolete another.** core-config's `pre-edit-stash.sh` runs *before* governance-pack's `deny-prod-paths.sh` so a stash exists even on a denied edit. That's harmless — git stash on a path Claude can't write is a no-op.

If `core-config` is missing, `install.sh` warns but proceeds. Each governance-pack hook works standalone.

---

## What each policy enforces, why, how to opt out

### `audit-gate.sh` — diff-size advisory

- **Enforces:** at session end (`Stop`), if `git diff --shortstat <main-or-master>...HEAD` shows > 50 LOC delta, prints an advisory message suggesting `/audit`.
- **Why:** matches roadmap-v1.1 §2.6 acceptance crit ("audit runs only above a complexity threshold"); cheap win without blocking iteration.
- **Opt-out:** `export GOVERNANCE_PACK_AUDIT_THRESHOLD_LOC=99999` (effectively disables) or remove the `Stop` entry from settings.

### `deny-prod-paths.sh` — production-surface block

- **Enforces:** Pre-edit/write/multi-edit to any path matching a glob in `~/.claude/prod-paths.txt`. Exit 2 ⇒ Claude sees the denial in transcript.
- **Default patterns:** `**/auth/**`, `**/security/**`, `**/billing/**`, `**/migrations/**`, `**/.env`, `**/secrets/**`, `**/*.pem`, `**/*.key`, `/home/criznguyen/projects/fansipan/**` (operator-specific; remove if you fork).
- **Why:** path-based hooks survive instruction-injection attacks ([Cursor PocketOS, Apr 2026](https://www.theregister.com/2026/04/27/cursoropus_agent_snuffs_out_pocketos/); [Replit DROP TABLE, Jul 2025](https://fortune.com/2025/07/23/ai-coding-tool-replit-wiped-database)). System-prompt "don't touch X" rules don't.
- **Opt-out per path:** comment the pattern in `~/.claude/prod-paths.txt`. Per session: `export GOVERNANCE_PACK_PROD_PATHS_FILE=/dev/null`. Per project: ship a project-scoped `prod-paths.txt` and override the env var in `.claude/settings.local.json`.

### `no-coauthor-trailer.sh` — clean commit attribution

- **Enforces:** PreToolUse on `Bash`, scoped to commands containing `git commit`. If the message contains `Co-Authored-By: Claude` (case-insensitive) OR `Co-Authored-By: ... <...@anthropic.com>`, blocks with exit 2 and message-to-retry. Other `Co-Authored-By: <human>` trailers pass through.
- **Why:** per `feedback_no_claude_coauthor` — operator preference for clean attribution. Generally useful for solo-dev / single-author repos.
- **Opt-out:** remove `no-coauthor-trailer.sh` entry from the `PreToolUse Bash` matcher in settings, OR if you want Claude listed: this hook is the one piece of the pack that's `opinions`-ish in spirit. Other users may simply not install it.

### `telemetry.sh` — local-only JSONL log

- **Enforces:** PostToolUse on every tool call. Appends one JSON line per call to `~/.claude/telemetry.jsonl` (timestamp, tool name, session id, project, success, exit code). No tool input is logged (avoids capturing secrets). Always exits 0.
- **Why:** without telemetry, lessons.md is sticky-note discipline. JSONL replays into `tools/replay-to-test.sh` per roadmap-v1.1 §8.6.
- **Opt-out:** `export GOVERNANCE_PACK_TELEMETRY=0` (or `false`/`no`). Inspect: `tail -f ~/.claude/telemetry.jsonl | jq .`.

### `permissions.deny` rules — settings-level guardrails

- `Read(./.env*)` / `Read(**/.env*)` / `Read(**/secrets/**)` / `Read(**/*.pem)` / `Read(**/*.key)` — secret-file blocklist. Survives any instruction-injection because it's enforced before Claude sees the file path.
- `Bash(curl *)` / `Bash(wget *)` — exfiltration prevention. Allow specific calls via project-scoped `allow` rules.
- `WebFetch` (deny) + allowlist for `docs.claude.com`, `code.claude.com`, `platform.claude.com`, `github.com`, `raw.githubusercontent.com`. Add domains in your local override.
- `permissions.defaultMode: "plan"` — every session starts in Plan Mode.

---

## Acceptance criteria (roadmap-v1.1 §2.3)

- [x] `.claude/settings.json` validates against Anthropic's published schema (top-level keys: `permissions`, `hooks`, `env`; `permissions.{allow,deny,defaultMode}`; hook event keys from the 13-event taxonomy).
- [x] `permissions.defaultMode` is `plan`.
- [x] `permissions.deny` includes `Read(./.env*)`, `Read(./secrets/**)`, `Bash(curl *)`.
- [x] Hook wiring covers the `core-config` 3-hook bundle (PreToolUse Bash + PreToolUse Edit/Write + PostToolUse Edit/Write) and adds 4 governance-pack hooks layered in the same matchers.
- [x] `.claude/freeze.json` ships with the schema doc but empty list (user populates per project).
- [x] `WebFetch` deny rule is present for non-allowlisted domains.
- [x] Synthetic test: `tests/tasks.yaml` covers the planted-commit-with-coauthor scenario.

---

## File tree

```
core/governance-pack/
├── README.md                              # this file
├── EXAMPLES.md                            # before/after settings.json diffs
├── install.sh                             # interactive merge installer
├── uninstall.sh                           # reverse + restore-from-backup
├── hooks/
│   ├── audit-gate.sh                      # Stop  · advisory if diff > 50 LOC
│   ├── _lib-audit-classify.sh             # sourced library · task-class + audit-id inference
│   ├── commit-msg-audit-check.sh          # git commit-msg · WARN/BLOCK on missing/non-PASS findings
│   ├── deny-prod-paths.sh                 # PreToolUse Edit/Write/MultiEdit · block by glob
│   ├── no-coauthor-trailer.sh             # PreToolUse Bash · block git-commit with Claude trailer
│   └── telemetry.sh                       # PostToolUse * · JSONL log
├── templates/
│   ├── global-settings.json               # ~/.claude/settings.json template
│   ├── project-settings.local.json        # <repo>/.claude/settings.local.json template
│   ├── prod-paths.txt                     # default denylist for deny-prod-paths.sh
│   └── freeze.json                        # empty per-project freeze schema
└── tests/
    └── tasks.yaml                          # 1 Promptfoo task: planted-coauthor commit
```

---

## Phase 8 audit gate (built-in)


charter v1.1 §2.2 says *deterministic enforcement beats prose enforcement*. Phase 8 (audit) was the last gate still depending on operator discipline. The `audit-builtin` feature ships three layers — Stop-hook advisory, git pre-commit soft-block, and CI hard-gate — without changing the audit producer (charter §2.3 independence-of-reviewer is preserved).

### What ships

| File | Layer | Behaviour |
|---|---|---|
| `hooks/_lib-audit-classify.sh` | shared library | `infer_task_class_from_message`, `infer_task_class_from_head`, `infer_audit_id` — sourced by every layer |
| `hooks/audit-gate.sh` (upgraded) | Stop hook | task-class-aware advisory; **always exits 0** |
| `hooks/commit-msg-audit-check.sh` | git commit-msg | local soft-block; WARN by default, BLOCK with `GOVERNANCE_PACK_AUDIT_STRICT=1` (registered as `commit-msg`, not `pre-commit`, so the hook reads the message being authored — see AUDIT-001 history) |
| `.github/workflows/audit-required.yml` (in claude-skills root) | CI workflow | PR-time hard gate; copy into your own repo to enforce on merge |

### Conventional-commits map

| Commit prefix | Task class | Audit required? | Pre-commit | CI workflow |
|---|---|---|---|---|
| `feat:`, `feature:` | feature | YES | WARN/BLOCK if missing PASS | enforce |
| `feat!:`, `feature!:` | system-change | YES | WARN/BLOCK if missing PASS | enforce |
| `fix!:`, `refactor!:`, `perf!:` | system-change | YES | WARN/BLOCK if missing PASS | enforce |
| `fix:`, `bugfix:`, `hotfix:` | bug-fix | NO (advisory only) | SKIP | skip-green |
| `refactor:`, `refactor(...)` | refactor | NO | SKIP | skip-green |
| `docs:`, `test:`, `chore:`, `ci:`, `build:`, `style:`, `perf:` | as-named | NO | SKIP | skip-green |
| `[skip audit]` footer (or `Audit-Skip: <reason>`) | bypassed | NO | SKIP (telemetry) | skip-green (telemetry) |
| `[force audit]` footer (or `Audit-Required: yes`) | forced | YES | enforce | enforce |
| (no recognized prefix) | unknown | YES (fail-closed) | WARN/BLOCK | enforce (fail-closed) |

The single source of truth for this map is the `case` statement in `hooks/_lib-audit-classify.sh`. Tech-spec §2 and the CI workflow reference the lib; they do not duplicate the logic.

### Environment variables

| Var | Effect | Default |
|---|---|---|
| `GOVERNANCE_PACK_AUDIT_STRICT=1` | Pre-commit hook exits 1 (BLOCK) on missing or non-PASS findings | `0` (WARN-only) |
| `GOVERNANCE_PACK_AUDIT_DISABLE=1` | Pre-commit hook is a no-op | `0` |
| `GOVERNANCE_PACK_AUDIT_THRESHOLD_LOC=<n>` | Stop-hook LOC threshold for the advisory | `50` |
| `GOVERNANCE_PACK_HOOKS_DIR=<path>` | Override classifier-lib lookup location (used in tests) | unset → falls back to script-sibling, then `~/.claude/hooks/governance-pack/`, then repo `core/governance-pack/hooks/` |

### Escape hatches

- Commit footer `[skip audit]` (or `Audit-Skip: <one-line reason>`) — bypasses the gate; both layers record `class=bypassed` to stderr/step-summary so abuse is observable. **Monitoring is operator-driven**: review GitHub Actions step summaries containing `class=bypassed` periodically (weekly cadence is a good default) and watch the local pre-commit stderr. There is no automated rollup shipped — the abuse signal is in the existing telemetry surface, not in a separate evaluator.
- Commit footer `[force audit]` (or `Audit-Required: yes`) — forces enforcement regardless of subject prefix. Useful when shipping a security-critical change behind a `chore:` prefix would otherwise skip the gate.
- `git commit --no-verify` — bypasses the local pre-commit hook only. The CI workflow still runs on PR open/sync; merge stays blocked until the artifact lands.

### Producing audit artifacts


**Operators with `safe-spawn-claude.sh`** (see [`opinions/safe-spawn-claude.sh`](../../opinions/) for setup) get budget/dedup guards. Symlink the script into a directory on your `PATH` (e.g. `~/bin/`) so the invocation is portable:

```bash
safe-spawn-claude.sh \
  /tmp/agent-audit-<id>.md \
  claude-opus-4-7 \
  audit-<id> \
  "$PWD"
```

> The wrapper lives in `opinions/` (operator-specific kit). `core/` doc paths stay PATH-relative so external adopters who symlink it elsewhere are not coupled to a maintainer's home directory.

**Adopters without `safe-spawn-claude.sh`** — vanilla setsid+nohup invocation produces the same artifact:

```bash
setsid nohup claude --dangerously-skip-permissions \
  -p "$(cat <<'EOF'
You are running the audit skill from claude-skills core/audit. Read in order:
  core/audit/prompts/independence-preamble.md
  core/audit/prompts/system.md
  core/audit/prompts/security-checklist.md
  core/audit/prompts/pe-checklist.md
End with the literal token `AUDIT-DONE id=<id> verdict=<v> findings=<n>`.
EOF
)" --model claude-opus-4-7 > /tmp/audit-<id>.log 2>&1 &
```

The CI gate works for both spawn paths because it only checks the artifact exists with `verdict=PASS`. It never invokes Claude itself, never holds an API key, never sees the implementation transcript.

### Multi-cycle handling


### `pre-audit-gate.sh` interaction

`core/core-config/hooks/pre-audit-gate.sh` is a `PreToolUse` hook that BLOCKS audit invocation when stub markers (`TODO`/`FIXME`/`XXX`/`pass # placeholder`/`not implemented`) are present in the diff. If a feature has stubs in non-audited paths and the audit cannot run, you have three options in order of preference:

1. **Scope narrowing** — set `CORE_CONFIG_AUDIT_SCOPE` (space-separated paths/globs) to the implementation directory; stubs in `tests/` or `docs/` will be ignored.
2. **Stub cleanup** — the deadlock is intentional (charter §2.1: stubs are fantasy, audit fantasy is worse than no audit). The deadlock IS the feature.
3. **Explicit override** — `CORE_CONFIG_AUDIT_GATE=0 safe-spawn-claude.sh ...` for the case where a stub is genuinely required (e.g. an interface placeholder for a not-yet-implemented adapter the spec marked OUT-OF-SCOPE).

### CI workflow installation

Adopters opt in by copying `.github/workflows/audit-required.yml` from this repo into `<your-repo>/.github/workflows/`. The workflow is shipped in the claude-skills repo (we dogfood it), but `install.sh` does NOT auto-install it into adopter repos — workflow YAML is high-trust and we do not write into `.github/workflows/` without an explicit operator gesture.

After your first PR triggers the workflow, configure branch protection in GitHub Settings → Branches → main → "Require status checks" and, in the dropdown of available checks, select the one whose name contains `Phase 8 audit gate`. The exact display string GitHub renders depends on your account/workflow setup — typically `audit-gate / Phase 8 audit gate` (job-name / display-name) but this can vary. Whatever appears in the dropdown after at least one workflow run on this repo is the canonical name; pick that one.

---

---

## Phase 2.1 enforcement (postcondition hook)


charter v1.1 §2.1 (anti-fantasy) names *"verify-before-claim"* as the symmetric twin of *read-before-edit*. v1.1.5 enforced read-before-edit at the hook layer (`pre-edit-stash.sh`); v2.0 closes the gap on the *post-claim* side. After every state-changing tool call (Bash, Edit, Write, MultiEdit, NotebookEdit) the `postcondition-hook.sh` PostToolUse hook walks `~/.claude/postconditions.d/*.sh`, runs every postcondition whose `# match=<tool>` and `# trigger=<glob>` header matches, and asserts the world matches the claim.

### What ships

| File | Purpose |
|---|---|
| `hooks/postcondition-hook.sh` | The PostToolUse dispatcher. Reads stdin JSON, walks `~/.claude/postconditions.d/*.sh`, runs each match under `timeout`, emits stderr `[postcondition-<status>]` + JSONL `event=postcondition` line. |
| `templates/postconditions.d/_self.sh` | TM1 integrity check — fires on Edit of any postcondition file; rejects bodies with no verification verb (catches paste-injected bare-`exit 0` gate-disable attempts). |
| `templates/postconditions.d/_template.sh` | Authoring skeleton operators copy when adding a new postcondition. |
| `templates/postconditions.d/{mkdir,git-push,edit-readback,write-stat,bash-exitcode,mv,rm,npm-install,pytest}.sh` | The 9 functional defaults — ~70% out-of-box coverage of state-changing patterns. |
| `templates/postconditions.json` | Mode config: `mode: shadow` default, `timeout_seconds: 5`, `max_stdout_chars: 200`, `default_class_gate: ["feature","system-change","forced","unknown"]`. |

### Mode (shadow vs blocking)

The hook ships **shadow-mode** by default per F2-7. Failures emit advisory stderr + JSONL telemetry but the hook always returns `exit 0`; the agent sees no signal and continues. After ~30 days of operator review of `event=postcondition status=fail` lines in `~/.claude/telemetry.jsonl` and confirmation that the FP rate is <5% on the golden eval, promote to **blocking-mode** with one line:

```bash
jq '.mode = "blocking"' ~/.claude/postconditions.json | sponge ~/.claude/postconditions.json
```

(Or `vim ~/.claude/postconditions.json` and edit `"shadow"` → `"blocking"`.) In blocking-mode the hook returns `exit 2` on any non-pass postcondition, and Claude Code surfaces the PostToolUse block message to the agent transcript per the lifecycle contract.

### Env vars

| Var | Effect | Default |
|---|---|---|
| `GOVERNANCE_PACK_POSTCONDITION_DISABLE=1` | Hook is a no-op for the session | `0` |
| `GOVERNANCE_PACK_POSTCONDITIONS_DIR=<path>` | Override the postcondition table location | `$HOME/.claude/postconditions.d` |
| `GOVERNANCE_PACK_POSTCONDITIONS_CONF=<path>` | Override the config file location | `$HOME/.claude/postconditions.json` |
| `POSTCONDITIONS_FORCE=1` | install.sh clobbers existing `~/.claude/postconditions.d/*.sh` files | unset (operator edits preserved) |

### Escape hatches

Three paths in order of preference (US5 in spec):

1. **Per-postcondition tweak.** Edit `~/.claude/postconditions.d/<name>.sh` directly. The files are hand-editable; for an NFS race condition, add a `sleep 0.1` before the verification. Operator edits survive `install.sh` re-runs unless `POSTCONDITIONS_FORCE=1`.
2. **Per-skill opt-out.** Add `postcondition_required: false` to the SKILL.md frontmatter for skills that genuinely should not gate on world-state assertions (e.g. interactive REPL skills).
3. **Per-session disable.** `export GOVERNANCE_PACK_POSTCONDITION_DISABLE=1` silences the hook entirely.

### Authoring postcondition snippets

Copy `core/governance-pack/templates/postconditions.d/_template.sh` to a new filename and fill in the header + body. The F2-6 *stealth cost* — adding a new state-changing skill costs roughly 10 lines of postcondition shell — is acknowledged here so operators see the bill upfront. Authoring rules (load-bearing per spec NG4 / TM5):

- **No LLM invocation in any postcondition body.** Forbidden literals: `claude -p`, `Agent(`, `anthropic.`, `@anthropic`. The reviewer pipeline `system-change:` audit checklist greps for these in any change to `templates/postconditions.d/`.
- **Deterministic shell only.** Postconditions assert *"world matches claim"*, never *"claim is semantically right"*. Semantic verification is the audit sub-agent's job (charter §2.3 independence-of-reviewer); duplicating it here collapses §2.3.
- **Local verification.** Network calls (e.g. `git fetch` in `git-push.sh`) are tolerated only when the existing 5s `timeout_seconds` cap is sufficient. Slow checks → explicit `# timeout_override=<sec>` (max 30s) per TM3.
- **No file modification.** Postconditions read; they do not write. TM2.

The `_self.sh` integrity check fires on every Edit of any file in the table and rejects bodies that contain no verification verb — a defense against paste-injected `~/.claude/postconditions.d/git.sh` returning bare `exit 0` (silent gate disable).

### Uninstall

Operator off-ramp (G7) — three commands fully reverse the feature:

```bash
bash core/governance-pack/uninstall.sh           # removes hook + de-registers from settings.json (preserves operator data)
bash core/governance-pack/uninstall.sh --purge   # also offers to remove ~/.claude/postconditions.{d,json}
git revert <postcondition-hook commit SHA>       # restores charter §2.1 prose-snippet enforcement
```

The `--purge` invocation prompts before each deletion so operator-customized postconditions are not silently lost.

---

## Phase 2.2 sub-clause #2 (quarantine-pack)


charter v1.1 §2.2 ("hooks > rules") gains a sub-clause #2 in v2.0: externally-sourced content (MCP user-content surfaces, `WebFetch`, `Read` of `**/uploads/**`) is **advisory-tagged at the boundary**. After every matched `PostToolUse` event, `core/quarantine-pack/hooks/wrap-mcp-output.sh` appends `[QUARANTINE-NOTICE: ...]` to the next-turn context via `hookSpecificOutput.additionalContext`. Trusted MCPs (`mcp__linear`, `mcp__github`, `mcp__jira`, `mcp__atlassian`, `mcp__claude_ai_Google_Drive`, `mcp__neural-memory`) opt out via `~/.claude/quarantine.d/trusted-mcp-allowlist.txt`.

### Advisory-only invariant

The hook does NOT rewrite `tool_response` (per F2-2 contract reality: PostToolUse fires AFTER the model has ingested the raw response). The advisory lands one turn AFTER the untrusted ingestion. The hook always exits 0 — it never blocks. Structural quarantine (rewrite at the boundary) is `feat:quarantine-structural` (T2.2), v2.1 contingent on Anthropic shipping `PreToolResultCommit` (charter §2.4-bis ASKS list entry (g)).

### Install / uninstall

Wired by `install.sh` Step 9 (after the postcondition Step 8). See [`core/quarantine-pack/README.md`](../quarantine-pack/README.md) for the full surface. Three-command uninstall:

```bash
bash core/governance-pack/uninstall.sh                    # removes hook + de-registers from settings.json
bash core/governance-pack/uninstall.sh --quarantine-only  # quarantine surface only (preserves postcondition gate)
bash core/governance-pack/uninstall.sh --quarantine-purge # also removes ~/.claude/quarantine.{d,json}
```

### Authoring postcondition snippets — STOP

Quarantine-pack is the **read-path** primitive; postcondition-hook is the **write-path** primitive. Quarantine-pack does NOT add postcondition snippets. See "Phase 2.1 enforcement" above for postcondition authoring.

---

## Cross-feature PreToolUse hook precedence

After a full v2.0 install, five PreToolUse hooks fire on shared write-path
matchers. See [`docs/conventions/pretooluse-hook-precedence.md`](../../docs/conventions/pretooluse-hook-precedence.md)
for the cost-cheapest-first ordering, the de-facto vs. recommended ordering
gap, and the procedure for adding a 6th PreToolUse hook.

## Citations

- Settings schema: <https://code.claude.com/docs/en/settings>
- 13-event hook taxonomy: <https://github.com/disler/claude-code-hooks-mastery>
- Hook safety motivation (Replit, Cursor): charter-v1.1.md §2.2
- Plan-mode default: <https://code.claude.com/docs/en/best-practices>
- Hook-level (not prompt-level) freeze rationale: review/EXPERT-1-methodologist.md F-strongest #3
- Co-author preference: user `feedback_no_claude_coauthor`
- Composes-with-core-config layering: roadmap-v1.1 §2.1 + §2.3
