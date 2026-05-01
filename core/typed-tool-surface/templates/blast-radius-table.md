# `blast_radius:` taxonomy

| Tier | Slug | Description | Examples |
|---|---|---|---|
| 1 | `read-only` | No state change anywhere. | `Read`, `Grep`, `Glob`, `WebSearch`, recall MCPs |
| 2 | `local-write` | Modifies operator's working tree only. | `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, write-mode MCPs to local sqlite |
| 3 | `repo-write` | Modifies version-controlled state (history-rewriting where applicable). | `Bash(git commit ...)`, `Bash(git tag ...)`, `Bash(git rebase ...)` |
| 4 | `network-write` | Writes to remote infrastructure. | `Bash(git push)`, `WebFetch` POST/PUT/DELETE, MCP write actions to GitHub/Linear/Jira |
| 5 | `external-side-effect` | Effects that cannot be cleanly reverted. | `Bash(rm -rf)`, `Bash(curl -X POST)` to payment APIs, `Bash(kubectl apply)`, deploy scripts |

The taxonomy is a strict ordering: each tier MUST be at least as restrictive as the previous one. Sandboxing tiers (`core/sandbox-default-on/`) cascade: a sandbox that allows tier-3 also allows tier-1 and tier-2; a sandbox that denies tier-3 implicitly denies tier-4 and tier-5.

## Choosing the right tier

When a tool fits multiple tiers, pick the **highest** (most restrictive). Examples:

- `Bash(echo "hi")` — read-only? It writes to stdout; but stdout is captured, not persisted. Tier 1 (read-only).
- `Bash(touch /tmp/foo)` — local-write. Tier 2.
- `Bash(git commit -m '...' --amend)` — repo-write. Tier 3.
- `Bash(git push --force origin main)` — network-write *and* effectively external-side-effect (overwrites others' work). Tier 5.

When in doubt, declare the higher tier. The cost of an over-tagged tier is a slightly more restrictive sandbox; the cost of an under-tagged tier is a missed gate-fire.
