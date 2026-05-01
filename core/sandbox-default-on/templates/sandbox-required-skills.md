# Skills that need `sandbox_required: false`

Skills whose canonical workflows REQUIRE sandbox-break behavior. The audit checklist for `system-change:` PRs verifies that any new skill claiming `sandbox_required: false` actually needs it.

| Skill | Why it needs sandbox-break |
|---|---|
| `core/sandbox-default-on/` | Itself — the install-flag writes to settings.json which the sandbox would consider "operator config write". |
| `opinions/safe-spawn-claude/` | Spawns nested Claude processes (forbidden under sandbox by default). |
| `core/git-force-push-gate/` | Operates on git remotes; network egress required. |
| (extend per-operator) | (your reason) |

The list is explicit, not implicit. A skill missing from this table that adds `sandbox_required: false` is reviewed in audit.
