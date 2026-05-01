---
name: sandbox-default-on
description: `governance-pack/install.sh --enable-sandbox` flag flips operator's `~/.claude/settings.json` `defaultMode: "sandbox"`. Per-skill opt-out via SKILL.md frontmatter `sandbox_required: false`. Documented rollback recipe at `templates/sandbox-rollback.md`. Configuration-only — no runtime hook (the Anthropic sandbox runtime does the enforcing). v2.0 Top-5 #5, charter §2.2 example list + §2.4-bis tracker entry (i).
type: governance
tools: Read, Bash
model: opus
blast_radius: read-only
sandbox_required: false
last-validated: 2026-04-29
---

# sandbox-default-on

Charter §2.2 example list + §2.4-bis tracker entry (i). Anthropic shipped the Claude Code sandbox runtime on 2025-10-19; the load-bearing primitive is `permissions.defaultMode: "sandbox"` in `~/.claude/settings.json`. This skill's installer flag flips that one key for the operator and documents the rollback so the operation is reversible.

## When to use

Operators whose work spans multiple repos and who want default-deny for every session unless an explicit `sandbox_required: false` opt-out lands on a SKILL.md.

## When NOT to use

- **For sessions that pip-install or build native code.** The default sandbox blocks network egress and write-outside-cwd; pip and native builds break. Use the per-skill opt-out OR run those sessions outside the sandbox.
- **As a substitute for `permissions.deny` rules.** Sandbox is the floor; deny rules are the ceiling. Both are required and neither replaces the other.

## Per-skill opt-out

Add `sandbox_required: false` to the SKILL.md frontmatter of any skill that genuinely needs to break out of the sandbox:

```yaml
---
name: my-installer-skill
sandbox_required: false
blast_radius: external-side-effect
---
```

The operator-facing convention: declaring `sandbox_required: false` is a load-bearing claim — the skill author is asserting that the sandbox WOULD break this skill. The audit checklist for `system-change:` PRs greps for this field and reviewers verify the claim.

## Install — one-shot

```bash
bash core/governance-pack/install.sh --enable-sandbox
```

Or post-install:

```bash
bash core/sandbox-default-on/install-flag.sh
```

The install-flag script:
1. Backs up `~/.claude/settings.json`.
2. Sets `permissions.defaultMode: "sandbox"` via jq merge.
3. Prints the rollback recipe.

## Rollback

`templates/sandbox-rollback.md` ships a 2-line recipe:

```bash
jq '.permissions.defaultMode = "default"' ~/.claude/settings.json > /tmp/s.json
mv /tmp/s.json ~/.claude/settings.json
```

## Forbidden in install-flag.sh (TM4)

Same TM4 list. Enforced by `tests/test-no-claude-spawn.sh`.

## Telemetry

The install-flag emits a single line on flip:

```json
{"event":"sandbox-default-on","ts":"...","action":"enabled|disabled|already-set","previous_mode":"...","new_mode":"sandbox","session_id":"install-time"}
```

## References

- Charter §2.2 example list + §2.4-bis tracker entry (i): [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
- Anthropic Claude Code sandbox runtime (2025-10-19; vendor-released, configuration-only).
- Rollback recipe: [`templates/sandbox-rollback.md`](./templates/sandbox-rollback.md)
