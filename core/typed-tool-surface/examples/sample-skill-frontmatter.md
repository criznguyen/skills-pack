# Sample SKILL.md frontmatter

## Style 1 — file reference

```yaml
---
name: my-skill
description: Does X.
type: governance
tools: Edit, Write
model: opus
blast_radius: local-write
args_schema: schemas/my-skill-args.schema.json
last-validated: 2026-04-29
---
```

## Style 2 — inline

```yaml
---
name: my-tiny-skill
description: Trivial helper.
type: utility
tools: Read
model: opus
blast_radius: read-only
args_schema:
  type: object
  required: ["query"]
  properties:
    query: { type: string, minLength: 3 }
  additionalProperties: false
last-validated: 2026-04-29
---
```

## Don't write `args_schema:` for tools whose args are already documented by Anthropic

`Bash`, `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Read`, `Grep`, `Glob` ship with built-in shapes. Authoring a duplicate schema is busy-work; the validator skips them when no per-skill schema is registered.

Schemas matter when YOUR skill exposes a domain-specific argument shape that the operator (or another agent) would benefit from typed validation against.
