# Changelog

skills-pack tracks the upstream `claude-skills` release cadence. This file
records only changes that affect installed behaviour for users of this
public mirror. For the full upstream history see
[`claude-skills` CHANGELOG](https://github.com/criznguyen/claude-skills/blob/main/CHANGELOG.md).

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) ·
versions: [SemVer](https://semver.org/spec/v2.0.0.html).

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
