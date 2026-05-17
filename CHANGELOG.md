# Changelog

skills-pack tracks the upstream `claude-skills` release cadence. This file
records only changes that affect installed behaviour for users of this
public mirror. For the full upstream history see
[`claude-skills` CHANGELOG](https://github.com/criznguyen/claude-skills/blob/main/CHANGELOG.md).

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) ·
versions: [SemVer](https://semver.org/spec/v2.0.0.html).

## v1.10.0 — 2026-05-18

Mirror of claude-skills v1.10.0 (upstream commit `1952ea8`, tag `v1.10.0`).
Harness-native enforcement mini-wave surfaced from comparison with the
shanraisshan/claude-code-best-practice repo. Replaces prompt-only governance
with first-party harness primitives where possible.

### Added

- **`core/coauthor-attribution-strip`** (NEW skill) — installs canonical
  `attribution.commit = ""` field into `~/.claude/settings.json` so the
  harness itself strips Anthropic/Claude trailers from generated commit
  messages. Idempotent install + matcher-aware drift recovery (jq-based,
  same pattern as governance-pack §13/§18). Project opt-out via
  `COAUTHOR_ATTRIBUTION_STRIP_DISABLE=1`. 7-case TMPHOME-isolated test.
- **`initialPrompt:` frontmatter** on `core/audit/SKILL.md` and
  `core/delta-code-review/SKILL.md` — injects PARANOIA-BUST PREAMBLE
  on every sub-agent invocation. Codifies the paranoia-break rule at
  the harness layer instead of via main-agent prompt boilerplate.
- **Frontmatter enrichment** on 13 core skill SKILL.md files — adds
  `paths:`, `when_to_use:`, `argument-hint:`, and where appropriate
  `disable-model-invocation: true` for background-knowledge skills
  (governance-pack-class hooks that fire automatically, not user-callable).
  Reduces wrong-skill activation noise + improves `/skills` autocomplete UX.

### Changed

- **`core/git-force-push-gate/hooks/git-push-gate.sh`** — pre-push refusal
  on commits whose body contains a `co-authored-by` trailer matching
  Claude / `@anthropic.com` email shape. Bypass via
  `GIT_FORCE_PUSH_GATE_ALLOW_CLAUDE_TRAILER=1`. 9-case test added.
- **`core/git-force-push-gate/tests/test-no-claude-spawn.sh`** — tightened
  TM4/NG6 regex from coarse `anthropic\.` to precise SDK invocation
  patterns (`anthropic.api/client/messages/Anthropic/...`, `@anthropic-ai/`,
  `from anthropic import`, `import anthropic`). Was firing on bare
  `anthropic.com` email-domain references inside the new trailer detection
  regex.

### Origin

shanraisshan/claude-code-best-practice repo comparison. Internal artifacts
(`audits/`, `docs/decisions/`, `docs/research/`) are NOT mirrored — see
upstream [`claude-skills` CHANGELOG](https://github.com/criznguyen/claude-skills/blob/main/CHANGELOG.md)
for full v1.10.0 history.

## v1.9.1 — 2026-05-04

Mirrors upstream claude-skills v1.9.1 — recovery patch landing two
missed-ships from the v1.8.0 commit. The v1.7.1 install.sh §13
root-cause fix was documented in CHANGELOG but never committed in
code form, and the v1.8.0 `multi-agent-merge-discipline` (MAMD)
skill shipped without an install § so operators ended up registering
the hook manually with a broken `${CLAUDE_PROJECT_DIR}/.claude/skills/...`
path that errors on every Bash invocation outside the skill's project.

### Fixed (v1.7.1 recovery)

- **`core/governance-pack/install.sh`** §13 (`file-write-stale-stat-refusal`
  registration) — now actually shipped on top of v1.9.0. The patch
  replaces the substring grep with a matcher-aware jq check (detect
  `cache-mtime-on-read` PostToolUse + `file-stat-check` PreToolUse
  separately, compare matcher to canonical, drop stale + add fresh on
  drift). The v1.7.1 CHANGELOG entry remains accurate; this release
  closes the gap between documentation and code.

### Added (v1.8.0 MAMD recovery)

- **`core/governance-pack/install.sh`** §18 (`multi-agent-merge-discipline`
  hook installation). Installs the hook globally to
  `~/.claude/hooks/multi-agent-merge-discipline/pre-commit-strip-gen.sh`
  with basename-aware drift recovery (handles legacy
  `${CLAUDE_PROJECT_DIR}/.claude/skills/...` registrations that were
  produced by manual installs in the v1.8.0 → v1.9.0 window).
- **`core/multi-agent-merge-discipline/SKILL.md`** — adoption checklist
  updated from per-project copy to global install model. Sub-agent
  worktrees no longer need to copy the hook into each worktree's
  `.claude/skills/`; the global hook resolves the project's
  `gen-paths.txt` from `${CLAUDE_PROJECT_DIR}` at runtime.

### Tests

- 37/37 governance-pack install tests PASS (was 35; +1
  `test-install-mamd-canonical.sh` covers §18 idempotency + drift
  recovery, +1 `test-install-matcher-canonical.sh` covers §13
  matcher-aware canonicalization).

## v1.9.0 — 2026-05-04

Mirrors upstream claude-skills v1.9.0 — slim ADOPT carved from deferred
full-shape live-discussion-skill proposal. Ships peer-discussion-budgeted
as the smallest addressable slice that earns telemetry toward whether
the deferred pieces (binding contract, LLM judge, operator escalation,
`teamwork` task class) are ever needed.

### Added

- **`core/peer-discussion-budgeted`** (NEW skill) — convention + hooks
  for sub-agent-to-sub-agent discussion threads via existing
  `claude-peers` MCP, with hard budget caps + auto-record.
  - **Convention**: peer messages whose first line matches
    `[discussion: <topic-slug>] <subject>` opt into budget tracking +
    auto-record. Untagged messages = casual peer chat (no behavior
    change).
  - **`hooks/budget-gate.sh`** PreToolUse on send_message enforces
    `PEER_DISCUSSION_MAX_TOPICS=5` × `PEER_DISCUSSION_MAX_ROUND_TRIPS=3`.
    Refusal at exit 2 with stderr advisory directing the agent to
    read existing record and decide unilaterally. Bypass:
    `PEER_DISCUSSION_BUDGETED_DISABLE=1`.
  - **`hooks/discussion-recorder.sh`** PostToolUse auto-appends
    each tagged message to `audits/discussions/<topic-slug>.md` +
    1-line ledger entry per topic (idempotent via content-hash).
  - 10 budget-gate tests PASS.
  - Origin: live ciscrm Wave 4.A.2 retrospective cross-domain
    coordination cases.

### Notes

- Advisory-only by design. Backward-compatible: untagged peer
  messages behave identically to pre-v1.9.0 (no opt-in friction).
- Telemetry: `opened` / `round-trip` / `halt-topic-cap` /
  `halt-session-cap` / `recorded` events emitted to
  governance-pack telemetry stream for v2-decision data.

## v1.8.0 — 2026-05-04

Mirrors upstream claude-skills v1.8.0 — two parallel-execution governance
additions surfaced from live ciscrm Wave 4.A.2 (6 parallel Opus
sub-agents + ~30 min × 4 sequential merges of mostly-mechanical
conflict resolution). Both backward-compatible.

### Added

- **`core/multi-agent-merge-discipline`** (NEW skill) — reduces
  orchestrator merge tax for parallel sub-agent worktrees.
  - Part A `pre-commit-strip-gen.sh` PreToolUse `Bash` hook detects
    `git commit` and unstages per-project allowlisted auto-generated
    files (configurable via
    `.claude/skills/multi-agent-merge-discipline/gen-paths.txt`).
    Orchestrator regenerates the union post-merge → eliminates ~80%
    of merge conflict surface (sqlc gen, ctxq, proto stubs, OpenAPI
    clients).
  - Part B handoff manifest convention (templates shipped) — sub-agents
    declare structured additions in JSON for programmatic merge of
    APPEND-ONLY shared files (RBAC, routes, wiring).
  - 6 hook tests PASS; full SKILL.md + CLAUDE.md + README.md +
    `gen-paths.txt.example`.

### Changed

- **`core/file-write-stale-stat-refusal`** v2.0 → v2.1 — adds
  same-session-write bypass. Fixes false-positive when this session's
  own lint/formatter (gofmt, prettier, biome, eslint) advances mtime
  AFTER PostToolUse cache hook stamps it. Cache schema gains
  `last_writer_session_id`; PreToolUse stat-check bypasses refusal
  when cached session_id matches current SESSION_ID and refreshes
  cache. Genuine cross-session drift still refuses. Legacy v2.0
  cache (no session_id) falls through to strict refusal.
  - 4 bypass tests PASS.

### Research

- **`docs/research/v1.8-ideas/`** holds the v1.8 design docs for
  both additions (origin from live ciscrm operator session 2026-05-04).

## v1.7.0 — 2026-05-04

Backlog ship — bundles 4 v2.x candidates from upstream claude-skills:
2 skill bug fixes (loop-circuit-breaker false-positive on legitimate
orchestration; file-write-stale-stat-refusal false-positive on
consecutive same-agent edits) + 2 new detectors (installed-hook-drift
reporter; pre-commit→commit-msg rename evasion grep in
git-force-push-gate).

### Changed

- **`core/loop-circuit-breaker/`** — per-tool-class counter. The single
  `iteration_count` (default cap 150) saturated 4-for-4 on real-world
  orchestration sessions because anti-fantasy reads consumed the cap
  before the build phase finished. v1.7.0 splits into:
  - `read_count` for `Read`, `Glob`, `Grep` — default ceiling 600
    (`LOOP_BREAKER_READ_CEILING`).
  - `write_count` for every other tool — default ceiling 150
    (`LOOP_BREAKER_WRITE_CEILING`).
  - `iteration_count` preserved as `read_count + write_count` for
    backward compat. `LOOP_BREAKER_ITER_CEILING` env still acts as a
    global cap on the sum (defaults to `read_ceiling + write_ceiling +
    100` when unset). Existing operator overrides keep working.
  - Halt precedence reordered to `write_count → read_count →
    iteration_count → usd_spent → hash_collisions`.
  - New test: `tests/test-tool-class-counters.sh` (7/7 PASS).

- **`core/file-write-stale-stat-refusal/`** — cache refresh on
  Edit/Write/MultiEdit. PostToolUse matcher widened from `Read` to
  `Read|Edit|Write|MultiEdit` so consecutive same-agent Edits no longer
  false-positive the drift check (the agent's own prior write advances
  mtime, which would otherwise look like external drift to the Read-only
  cache). Race window between PreToolUse stat check and PostToolUse
  cache update is milliseconds; a malicious external write that lands in
  that gap will slip past until the next agent action on the file. Test
  count moves 5/5 → 8/8.
  - **Operator action required** for adopters with v1.6.0 install: live
    `~/.claude/settings.json` PostToolUse matcher (currently `"Read"`)
    needs to change to `"Read|Edit|Write|MultiEdit"`. Re-run
    `bash core/governance-pack/install.sh` OR edit manually. Without
    this update, the v1.6.0 same-agent-Edit false positive persists.

- **`core/git-force-push-gate/`** — `pre-commit→commit-msg` rename
  evasion detection. New `REASON` class `hook_rename` blocks the rename
  on every branch when both `.git/hooks/pre-commit` AND
  `.git/hooks/commit-msg` literals appear as argv tokens in the same
  shell-meta chunk (covers `mv`, `cp`, `install`, `ln`, and `git mv`
  variants). Argv-parse-aware so literal mentions in commit-message
  bodies are ignored. Test count moves 12/12 → 17/17.
  - Known limitations (documented in SKILL.md): multi-chunk obfuscation
    and shell-var path expansion are NOT detected. The gate is a
    guardrail against accidents and naive evasion, not a hardened
    sandbox.

### Added

- **`core/installed-hook-drift/` skill (NEW)** — reporter that compares
  each installed hook in `~/.claude/hooks/<group>/<hook>.sh` against the
  canonical version in `<repo>/core/<group>/hooks/<hook>.sh`. Flags
  drift (sha256 mismatch) and orphans (installed hook with no canonical
  counterpart). JSONL output on stdout; exit 0 always (reporter, not
  enforcer). Useful as a sanity check before filing "skill is broken"
  issues — local drift from manual edits, partial git pulls, or
  third-party tool overwrites is a common cause of unexplained skill
  behavior. NOT auto-installed; operator opts in.

### Backwards compatibility

| Change | Impact | Migration |
|---|---|---|
| `LOOP_BREAKER_READ_CEILING` (new env, default 600) | Strictly looser cap on read-class tools | None — default absorbs existing usage. |
| `LOOP_BREAKER_WRITE_CEILING` (new env, default 150) | Same as v1.6.0 single-counter cap, but only on write-class | None — write-runaway behavior preserved. |
| `LOOP_BREAKER_ITER_CEILING` | Still works as global sum cap | None — existing overrides apply. |
| `cache-mtime-on-read.sh` matcher | Hook accepts Read/Edit/Write/MultiEdit | Re-run `core/governance-pack/install.sh` to widen the live PostToolUse matcher. |
| New skill `core/installed-hook-drift/` | Pure addition; no installer wiring | None — opt-in. |
| `git-force-push-gate` `hook_rename` REASON | New blocker on every branch | None — paths that don't rename pre-commit→commit-msg are unaffected. |

## v1.6.0 — 2026-05-04

### Added

- **`core/fix-root-cause/` skill** — codifies the "fix the root cause, no
  workaround" rule. When the agent considers a workaround, the skill
  triggers a 4-question gate; the workaround is accepted ONLY if (1)
  there is documented time pressure AND (2) the workaround is comment-
  tagged in source AND (3) the follow-up is tracked with an owner and
  deadline AND (4) the reversibility plan is documented. Any NO answer
  rejects the workaround and sends the agent back to the root-cause
  path. Source: a real session where a sub-agent renamed a token in
  narrative prose (typography swap on `foo.x.y`) to dodge a `grep -c`
  verify check rather than fix the underlying scope drift; the
  operator caught it during a hand spot-check and mandated codification
  as a standalone skill.
- **5 sub-principles** (each with implementation hint in `SKILL.md`):
  1. **No typographical evasion** — never rename a token to dodge a
     grep; fix the check or fix the underlying drift.
  2. **No error suppression without diagnosis** — `2>/dev/null`,
     `|| true`, `try/except: pass`, JS `.catch(() => {})` need a
     one-line WHY comment OR a specific known-non-fatal case named.
  3. **No scope-narrowing escape** — "I scoped to file X" is rejected
     unless the spec explicitly authorizes the narrowing.
  4. **No hardcoded sentinel value** — fail loudly on missing required
     config; do not silently default to `100` / `null` / etc.
  5. **No skipping failing tests** — `t.Skip("flaky")` rejected without
     explicit ticket + owner + deadline.
- **3 prompt files**:
  - `prompts/decision-tree.md` — 4-question gate as a mermaid
    flowchart + plain-text fallback (T5+T6 ensure both shapes ship).
  - `prompts/anti-pattern-catalog.md` — 12 BAD-vs-GOOD code examples;
    each entry has BAD code → GOOD code → 1-line explanation. Coverage
    map: principle 2 (error suppression) gets 4 entries reflecting
    operator-observed incident frequency.
  - `prompts/workaround-template.md` — standard `// WORKAROUND:`
    comment shape (5 required fields: WORKAROUND / Why root cause not
    fixed / Follow-up / Reversibility / Author) + 5-question smell
    test the operator/auditor runs before accepting any workaround.
- **Tests** — `core/fix-root-cause/tests/test-skill-shape.sh` (9 cases,
  all PASS): T1 SKILL.md front-matter `name:`+`description:`; T2
  README.md non-empty; T3 all 3 prompt files exist; T4 catalog has
  ≥12 entries (`## Entry N` count); T5 decision-tree has mermaid
  block; T6 decision-tree has plain-text fallback section; T7
  workaround-template has all 5 standard fields; T8 description is
  200..900 chars; T9 SKILL.md references all 3 prompt files
  (rename-drift guard).

### Composes with

- `core-config` (anti-fantasy is the sibling rule for facts; this
  skill extends the same "verify before claim" discipline to fixes).
- `audit` — auditor uses anti-pattern-catalog as a PE-dimension
  checklist during cycle review.
- `delta-code-review` — reviewer flags suppressed errors and
  validates `// WORKAROUND:` comments against the template.
- `governance-pack` — anti-pattern surface enumeration inherits the
  catalog.

### Backwards compatibility

Pure additive — new skill directory `core/fix-root-cause/`, no hooks,
no `settings.json` edits, no installer changes. Existing v1.5.0 /
v1.4.x skills untouched. Adoption is `git pull` + the auto-attach
trigger phrases in `SKILL.md` §"When to apply".

### Upstream commits

Mirrored from `criznguyen/claude-skills` `e5254b9` + `9e0a0b5` +
`0b51c77` + `3e39002` (tag `v1.6.0`). Audit cycle-1 PASS, 23/23
probes green at release.

### Intentionally NOT mirrored

- `docs/sdlc/spec/v1.6.0-fix-root-cause/...`,
  `docs/sdlc/architecture/v1.6.0-fix-root-cause/...`,
  `docs/sdlc/tech-spec/v1.6.0-fix-root-cause/...` — claude-skills
  repo-internal SDLC artifacts.
- `audit-report-cycle-*.md` — claude-skills repo-internal audit
  cycle reports.

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
