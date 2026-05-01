---
name: typed-tool-surface
description: Convention + PreToolUse(`*`) validator. Each SKILL.md declares `blast_radius:` ∈ {read-only, local-write, repo-write, network-write, external-side-effect} and `args_schema:` (relative path or inline JSON Schema). The schema-validate hook reads frontmatter at session start, caches to `~/.claude/sessions/<sid>/skill-schemas.json`, and validates `tool_input` per call via jq (or python jsonschema fallback). Failure → advisory or exit 2 (configurable per-skill). v2.0 Top-5 #4, charter §2.2 mechanism.
type: governance
schema_version: "2.0"
tools: Read, Bash
model: opus
blast_radius: read-only
last-validated: 2026-04-29
---

# typed-tool-surface

Charter §2.2 ("hooks > rules") mechanism upgrade. Pre-v2.0, hooks read prose patterns to decide refusal — fragile to rename / typo. v2.0 promotes the contract: hooks read **typed** `blast_radius` + JSON Schema for tool args. Schema-validation runs PreToolUse before the agent's call dispatches.

## When to use

Auto-installed by `core/governance-pack/install.sh` Step 16. Every SKILL.md frontmatter MUST declare `blast_radius:`. The 22 v1.1.6 FULL-coverage skills migrate via the bulk-convert protocol (`README.md` §Migration); new v2.0 skills declare both fields from inception.

## When NOT to use

- **As semantic verification.** The validator only checks tool_input against the declared schema; it does NOT verify the *outcome* of the call. Postcondition-hook (`core/governance-pack/hooks/postcondition-hook.sh`) is the post-call partner.
- **For built-in tools without an authored skill.** `Bash`, `Edit`, etc. ship with implicit schemas; the validator skips them when no `args_schema:` is registered.

## blast_radius taxonomy

| Value | Examples |
|---|---|
| `read-only` | `Read`, `Grep`, `Glob`, `WebSearch`, `mcp__neural-memory__*recall*` |
| `local-write` | `Edit`, `Write`, `MultiEdit`, `NotebookEdit` |
| `repo-write` | `Bash(git commit ...)`, `Bash(git tag ...)` |
| `network-write` | `Bash(git push ...)`, `WebFetch` (write-shaped POST), `mcp__github__*pr*` |
| `external-side-effect` | `Bash(rm -rf ...)`, `Bash(curl -X POST ...)`, payment APIs |

The taxonomy is a *decision-relevant ordering*: each tier MUST be at least as restrictive as the previous one. `governance-pack/install.sh --enable-sandbox` (E.8) reads the same field to apply tiered sandboxing.

## args_schema declaration

Two styles:

**1. File reference (preferred for long schemas):**

```yaml
---
name: my-skill
blast_radius: local-write
args_schema: schemas/my-skill-args.schema.json
---
```

**2. Inline (for tiny schemas):**

```yaml
---
name: my-tiny-skill
blast_radius: read-only
args_schema:
  type: object
  required: ["query"]
  properties:
    query: { type: string, minLength: 3 }
---
```

## Forbidden in hook bodies (TM4)

`hooks/schema-validate.sh` is shell + jq + python3-fallback only. Enforced by `tests/test-no-claude-spawn.sh`.

## Telemetry

```json
{"event":"schema-validate","ts":"...","tool":"...","decision":"pass|fail|skip","skill":"...","violations":[],"session_id":"..."}
```

Privacy invariant: `violations[]` carries JSON-pointer paths only (e.g. `/file_path`), NEVER the violating value (would log credentials etc).

## Performance budget

Median per-call latency target ≤ 5 ms (jq schema-check on warm cache). Hard timeout 5000 ms.

## Migration

The bulk-convert of 22 v1.1.6 FULL-coverage skills is deferred to a follow-up PR per research §4 Top-5 #4 binding F2-5. This skill ships the convention + validator only; existing skills remain `blast_radius: unspecified` until migrated.

## References

- Charter §2.2 mechanism: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
- jq (MIT/BSD) — JSON Schema validation library: <https://github.com/stedolan/jq>
