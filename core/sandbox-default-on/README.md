# `sandbox-default-on` — installer flag for `permissions.defaultMode: "sandbox"`

v2.0 Top-5 #5. Charter §2.2 example list + §2.4-bis tracker entry (i).

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body. |
| `CLAUDE.md` | Agent-facing fragment. |
| `install-flag.sh` | The flag implementation, invoked by `governance-pack/install.sh --enable-sandbox`. |
| `templates/sandbox-rollback.md` | 2-line operator rollback recipe. |
| `templates/sandbox-required-skills.md` | Table of v1.1.6 skills that need `sandbox_required: false`. |
| `tests/test-flag.sh` | Smoke-test against a tmp HOME. |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |
| `examples/sample-settings.json` | post-flip settings.json. |

## Install

```bash
bash core/governance-pack/install.sh --enable-sandbox     # via governance-pack
bash core/sandbox-default-on/install-flag.sh              # standalone
```

The flag is idempotent: re-running detects `defaultMode` already set to `sandbox` and emits `action=already-set` telemetry without re-touching the file.

## Rollback

See `templates/sandbox-rollback.md`.

## Why configuration-only (no runtime hook)

Anthropic ships the sandbox runtime; we ship the flip-the-switch installer. There is no value in re-implementing sandbox semantics in shell. Charter §2.4 ("compose primitives, don't reinvent") applies.

## References

- Charter §2.2 + §2.4-bis: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
