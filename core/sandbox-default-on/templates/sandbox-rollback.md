# sandbox-default-on — rollback recipe

Two lines reverse the flip:

```bash
jq '.permissions.defaultMode = "default"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
# Restart Claude Code or run /reload to pick up the change.
```

This restores the pre-sandbox `defaultMode` (`"default"` is the vendor default; if your operator config used `"plan"` before, replace `"default"` with `"plan"`).

## Verify

```bash
jq '.permissions.defaultMode' ~/.claude/settings.json
# Expected: "default"
```

## When to roll back

- Native build / pip install pipelines that the sandbox blocks.
- Network egress to non-allowlisted hosts.
- Any session where the sandbox cost > the safety benefit.

## When NOT to roll back

- "It is annoying" is not a sufficient reason. The sandbox is the default-on enforcement of charter §2.2 mechanism (typed-tool-surface). Per-skill opt-out (`sandbox_required: false`) is the surgical alternative.
