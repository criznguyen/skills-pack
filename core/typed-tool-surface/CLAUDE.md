# typed-tool-surface — skill-author guidance

When you author a new SKILL.md, declare BOTH `blast_radius:` and (if your tools have non-trivial argument shapes) `args_schema:`. The 5-tier taxonomy:

- `read-only` — `Read`, `Grep`, recall, search.
- `local-write` — `Edit`, `Write`, `MultiEdit` to operator's working tree.
- `repo-write` — `Bash(git commit / tag)` — modifies version control.
- `network-write` — `Bash(git push)`, `WebFetch` POST, MCP write actions.
- `external-side-effect` — `Bash(rm -rf, curl -X POST)`, payment, deploy.

## Writing a JSON Schema for tool args

Goal: catch the most common malformed `tool_input` shapes before dispatch. The schema is NOT meant to be exhaustive — it is a guard against egregious typos.

```json
{
  "type": "object",
  "required": ["file_path"],
  "properties": {
    "file_path": { "type": "string", "minLength": 1, "pattern": "^/" },
    "old_string": { "type": "string" },
    "new_string": { "type": "string" }
  },
  "additionalProperties": false
}
```

Three failure modes the schema catches well:
1. Missing required fields (typo: `filePath` instead of `file_path`).
2. Wrong type (passing a number where a string is expected).
3. Forbidden combinations (`additionalProperties: false`).

Three failure modes the schema does NOT catch (postcondition-hook does):
1. The operation succeeded but the wrong content landed.
2. The path matched but the file is corrupted.
3. The agent's *intent* was wrong (purely semantic).

## Frontmatter examples

See `examples/sample-skill-frontmatter.md` for both styles (file-reference and inline).

End of `core/typed-tool-surface/CLAUDE.md`.
