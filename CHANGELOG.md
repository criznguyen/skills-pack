# Changelog

skills-pack tracks the upstream `claude-skills` release cadence. This file
records only changes that affect installed behaviour for users of this
public mirror. For the full upstream history see
[`claude-skills` CHANGELOG](https://github.com/criznguyen/claude-skills/blob/main/CHANGELOG.md).

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) ·
versions: [SemVer](https://semver.org/spec/v2.0.0.html).

## v1.5.0 — 2026-05-04

### Added

- **`core/anti-ai-ux/` skill** — five UX patterns the agent applies by
  default when generating user-facing UI for agent-driven products. Closes
  the gap between the agent-side anti-fantasy discipline (already enforced
  by `core-config` / `loop-circuit-breaker` / `pre-edit-stash`) and the
  user-facing code the agent BUILDS. The skill auto-attaches when both a
  UI-framework signal AND an AI-product signal are present in the project.
- **5 principles, 5 prompt files** with React, Vue 3, Svelte 5, Flutter,
  and SwiftUI examples for each:
  1. **Real-time progress** — token streaming + named-status strings
     (no opaque "Thinking…").
  2. **Visible rollback** — undo stack + persisted history for every
     destructive AI-driven action.
  3. **Explain reasoning** — decision-card schema with confidence band
     (certain / likely / speculative), sources, alternatives.
  4. **Consent before destructive** — preview → confirm flow with
     reversibility classification + typed-confirmation for high-blast-radius
     ops + server-side idempotency keys.
  5. **Show data flow** — source → action → destination breadcrumb with
     freshness chips and pre-call/post-call LLM cost surface.
- **Compose graph** — pairs with `claude-api` (API-side streaming + cost
  primitives feed the UI patterns), `core-config` (anti-fantasy applies to
  UI code too), `simplify` (don't over-engineer the anti-AI envelope).
- **`core/anti-ai-ux/tests/test-skill-shape.sh`** — 8 shape tests including
  a T8 framework-coverage drift guard (fails if any of react / vue /
  svelte / flutter / swiftui is dropped from any prompt). 8/8 PASS at
  release.

### Backwards compatibility

Pure additive: new `core/anti-ai-ux/` directory, no hook changes, no
`settings.json` edits, no installer changes. Adopters who do not generate
UI code are unaffected.

### Upstream commits

- `f599d2f` feat(skills): v1.5.0 — add anti-ai-ux skill (5 user-facing UI principles)
- `987a0d6` fix(skills): Svelte 5 coverage in reasoning/consent/data-flow + T8 drift guard
- `0850f34` merge: v1.5.0 anti-ai-ux skill on top of v1.4.4 hotfix
- `601c3ab` chore(skills): v1.5.0 audit cycle-2 PASS

## v1.4.4 — 2026-05-03

Hotfix triple — closes one INFO-grade audit finding plus two known UX
papercuts surfaced during ship.

### Fixed

- **`deny-prod-paths.sh` jq fallback** (`core/governance-pack/hooks/`).
  Probing jq with `command -v jq` accepted a broken jq SYMLINK in PATH;
  `jq -r …` then failed silently with empty output → empty `file_path` →
  silent denylist bypass. Replaced with a `have_jq()` helper that runs
  `jq --version` to confirm the binary actually executes; same hardening
  applied to the python3 fallback. Test
  `core/governance-pack/tests/test-deny-prod-paths.sh` gains case A5
  (broken-jq fallback): installs a `jq` shim that always exits 1 and
  confirms the hook still blocks via the python3 fallback (5/5 PASS — was
  4/4).
- **`block-destructive.sh` doc-context whitelist** (`core/core-config/hooks/`).
  The pattern matcher previously tripped on its own rule descriptions:
  `git commit -m "block rm -rf /"` or `echo "rule blocks dd of=/dev/sd*"`
  were flagged as destructive. v1.4.4 adds a doc-context whitelist BEFORE
  the destructive scan: commands solely shaped as
  `git commit` / `git tag` / `printf` / `echo` / `cat > …` / `cat >> …`,
  or containing a heredoc `<<EOF` marker, exit 0 silently. Chained
  commands (`&&`, `;`, `|`, `||`) bypass the whitelist so
  `git commit && rm -rf /` still blocks on the destructive half. Test
  `core/core-config/tests/test-block-destructive.sh` gains 5 cases
  (D15-D19); 33/33 PASS — was 28/28.
- **`governance-allow.txt` pattern format docs.** Patterns are matched
  against ABSOLUTE paths (`/home/.../internal/auth/foo`), so bare
  `internal/auth/**` silently does NOT match — operators saw the deny
  fire even with an allow-file in place. Added a "Pattern format" section
  to `core/governance-pack/README.md` with RIGHT (`**/internal/auth/**`)
  vs WRONG (`internal/auth/**`) examples; `core/governance-pack/EXAMPLES.md`
  Case 5 updated to use the canonical `**/`-prefixed form. The hook
  stderr now also emits a HINT line pointing at the prefix requirement
  when an allow-file is present but no pattern matched.

### Tests

- `test-block-destructive.sh`: 28/28 → 33/33 PASS (+5 doc-context cases).
- `test-deny-prod-paths.sh`: 4/4 → 5/5 PASS (+1 broken-jq fallback case).

### Backwards compatibility

All changes strictly additive. The jq probe is more conservative — paths
that previously bypassed the denylist via broken-jq now correctly block,
no new false positives. The doc-context whitelist passes commands that
previously blocked on their own doc text — strictly looser, no new blocks.
Projects already using `**/`-prefixed allowlist patterns see no behavior
change.

### Upstream commits

- `7ed5778` fix(skills): v1.4.4 — 3 hotfixes (jq fallback + doc-context whitelist + allowlist prefix docs)

## v1.4.3 — 2026-05-03

### Added

- **Per-project governance allowlist** — `<project_root>/.claude/governance-allow.txt`.
  Solves the v1.4.2 universal-denylist over-fire problem: when a project does
  intensive work in protected paths (audit-remediation on `internal/auth/`,
  schema-redo across `db/migrations/`, billing refactor), the operator lists
  glob patterns that win over the universal denylist FOR THIS PROJECT ONLY.
  Universal protection for every other project is preserved.
- **Allow-wins semantics** — `deny-prod-paths.sh` walks up from the candidate
  file's directory looking for `.git/`. The first ancestor with `.git/` is
  the project root. If `.claude/governance-allow.txt` exists and a glob
  matches, the write is allowed (`exit 0`) AND audit-logged to
  `.claude/state/governance-allow.jsonl` for traceability — every allowed
  write that would otherwise have been denied is recorded with
  `{ts, tool, file_path, matched_pattern, allow_file, reason}`.
- 2 new env overrides for advanced operators / tests:
  `GOVERNANCE_PACK_ALLOW_FILE` and `GOVERNANCE_PACK_AUDIT_LOG_FILE` (both
  honor `/dev/null` for session-only disable).
- README "Per-project allowlist (v1.4.3+)" section + EXAMPLES Case 5
  walkthrough.

### Changed

- `core/governance-pack/hooks/deny-prod-paths.sh` — allowlist check inserted
  BEFORE the existing denylist loop. Behavior for projects without an
  allow-file is byte-for-byte unchanged. Stderr deny message gains a hint
  pointing at the allowlist mechanism.

### Backwards compatibility

ALL projects without `.claude/governance-allow.txt` see ZERO behavior change.
The allowlist is opt-in per-project; existing universal denylist (v1.4.2
patterns: `**/auth/**`, `**/security/**`, `**/billing/**`, `**/migrations/**`,
`**/.env*`, `**/secrets/**`, `**/credentials/**`, `**/*.pem`, `**/*.key`,
`**/id_rsa*`, `**/terraform/prod/**`, etc.) still protects every project
that has not opted in.

### Upstream commits

- `7f71bbd` feat: v1.4.3 governance-pack per-project allowlist with audit-log
- `83590af` merge: v1.4.3 governance-allow on top of v1.4.2.1

## v1.4.2.1 — 2026-05-03

### Fixed

- **CRITICAL hotfix**: `pre-edit-stash.sh` previously used
  `git stash push --keep-index --include-untracked --quiet -m … -- <path>`,
  which MOVES the targeted file's uncommitted changes off the worktree
  (= silent revert to HEAD) before the agent's Edit/Write runs. Sequential
  Edit/Write operations on the same file lost all but the last change;
  multi-step refactors silently reverted between tool invocations.
- Replaced `stash push` with `git stash create` + `git stash store`. The
  `create` primitive snapshots the worktree into a stash commit object
  WITHOUT touching the working tree; `store` records it in the stash list.
  The operator's recovery contract (`git stash list` shows pre-edit
  snapshots) is preserved; the silent-revert side-effect is gone.
- `git stash create` is content-addressed by the worktree tree, so multiple
  invocations against an unchanged worktree dedup to 1 stash entry. JSONL
  log still grows per-invocation so operators can audit which file each
  call targeted.

### Upstream commits

- `dc367b9` fix: v1.4.2.1 pre-edit-stash uses stash create/store, no longer reverts worktree

## v1.4.2 — 2026-05-03

### Fixed

- **CRITICAL — vapor refs closed.** `core/core-config/` now actually ships
  the 3 hooks the README, EXAMPLES, and `governance-pack/templates/global-settings.json`
  reference: `block-destructive.sh`, `pre-edit-stash.sh`, `lint-touched.sh`.
  Operators who merged `governance-pack/templates/global-settings.json` into
  `~/.claude/settings.json` previously hit `exit 127` on every Bash / Edit /
  Write / MultiEdit PreToolUse + PostToolUse because the referenced hook
  files did not exist on disk. v1.4.2 materializes them.
- Hardened `pre-edit-stash.sh` deny pattern to cover modern secret-file
  conventions: `id_ed25519*`, `id_ecdsa*`, `*.cert`, `*.crt`, `*.p12`,
  `credentials.json`, `.npmrc`, `.dockercfg`, `.pgpass`, `.envrc`,
  `.aws/credentials*`, `.aws/config*`.
- Hardened `block-destructive.sh` `rm` rules with a flag-cluster-tolerant
  prefix covering long-form (`rm --recursive --force /`) and multi-target
  (`rm -rf foo /`) shapes — applied to all 5 `rm` rules.
- `BLOCK_DESTRUCTIVE_DISABLE` opt-out now exits 0 silent (no stderr advisory).

### Added

- `core/core-config/hooks/block-destructive.sh` — PreToolUse `Bash` regex
  blacklist (`rm -rf /`, `mkfs`, `dd of=/dev/sd*`, fork bomb, `terraform
  destroy` w/o `-target`, `kubectl delete ns --all`, `shutdown`/`reboot`/
  `halt`/`poweroff`, …). Composes UNDER `blast-radius.sh`. Opt-out:
  `BLOCK_DESTRUCTIVE_DISABLE={1,true,TRUE}`.
- `core/core-config/hooks/pre-edit-stash.sh` — PreToolUse `Edit|Write|
  MultiEdit` insurance `git stash` of every file the agent is about to
  modify so the operator can recover via `git stash list` if the edit is
  wrong. JSONL audit log at `~/.claude/state/pre-edit-stashes.jsonl`.
  Always exits 0 (never blocks). Opt-out: `PRE_EDIT_STASH_DISABLE=…`.
- `core/core-config/hooks/lint-touched.sh` — PostToolUse `Edit|Write|
  MultiEdit` per-project linter dispatcher (Python `ruff`→`flake8`,
  JS/TS local `node_modules/.bin/eslint`, Rust `rustfmt --check` only when
  `Cargo.toml` exists, Shell `shellcheck`, JSON `jq`). **Shadow-mode
  default**; promote to blocking with `LINT_TOUCHED_BLOCKING=1`. Telemetry
  sink: `~/.claude/telemetry.jsonl`.
- `core/core-config/install.sh --project <path>` flag: additionally
  installs `lint-touched.sh` into `<path>/.claude/hooks/` for project-scope
  matchers (the matcher only fires inside `<path>`).

### Changed

- `core/core-config/README.md` acceptance criteria (§"Acceptance criteria")
  flipped to all-pass for the original 7-box roadmap §2.1 grid.
- `core/governance-pack/install.sh` step 5 compose-with-core-config check
  now points operators at the explicit installer command.

### Upstream commits

Mirrored from `criznguyen/claude-skills` `c2bc254` + `dc67198` + `49863e7`
(tag `v1.4.2`). Audit cycle-1 BLOCK → cycle-2 PASS, 0 HIGH/MEDIUM/LOW
findings open at release.

### Intentionally NOT mirrored

- `core/core-config/tests/test-*.sh` — tests stay upstream-internal so
  this public pack's `tests/` surface remains the single `tasks.yaml`
  promptfoo smoke task.
- `docs/sdlc/...` audit reports and SDLC artifacts — claude-skills
  repo-internal.

## Earlier

See [`VERSION`](VERSION) and the upstream
[`claude-skills` changelog](https://github.com/criznguyen/claude-skills/blob/main/CHANGELOG.md).
