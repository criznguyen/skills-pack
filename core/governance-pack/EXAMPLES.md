# `governance-pack` — before/after `settings.json` diffs

Four common starting states. Each shows the original, the merge result, and what changed. The installer (`install.sh`) is what produces the right column. Examples here are illustrative; run `install.sh --dry-run` to see your actual delta.

---

## Case 1 — empty `~/.claude/settings.json`

### Before

```json
{}
```

### After

The full template is copied verbatim (`cp templates/global-settings.json ~/.claude/settings.json`). See `templates/global-settings.json` — 7 hooks across 3 events, 19 deny rules, 5 allow rules for trusted WebFetch domains.

### What changed

Everything. New file. No backup written (nothing to back up).

---

## Case 2 — user already has `permissions` but no `hooks`

### Before

```json
{
  "permissions": {
    "defaultMode": "default",
    "allow": ["Bash(npm test *)"],
    "deny": ["Read(./.env)"]
  }
}
```

### After

```json
{
  "permissions": {
    "defaultMode": "plan",
    "allow": [
      "Bash(npm test *)",
      "WebFetch(domain:docs.claude.com)",
      "WebFetch(domain:code.claude.com)",
      "WebFetch(domain:platform.claude.com)",
      "WebFetch(domain:github.com)",
      "WebFetch(domain:raw.githubusercontent.com)"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Read(./secrets/**)",
      "Read(**/secrets/**)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      "Read(**/id_rsa*)",
      "Bash(curl *)",
      "Bash(wget *)",
      "Bash(rm -rf /*)",
      "Bash(rm -rf ~/*)",
      "Bash(git push --force *)",
      "Bash(git push -f *)",
      "Bash(git reset --hard *)",
      "Bash(terraform destroy *)",
      "Bash(kubectl delete *)",
      "WebFetch"
    ]
  },
  "hooks": { /* full hook block from template */ }
}
```

### What changed

- `permissions.defaultMode`: `"default"` → `"plan"` *(merge took the new value)*
- `permissions.allow`: added 5 WebFetch domain entries
- `permissions.deny`: kept `Read(./.env)`, added 18 more entries
- `hooks`: added 7 hooks across 3 events
- Backup at `~/.claude/settings.json.bak.20260428-093000`

> **Note on merge semantics.** Both `jq -s '.[0] * .[1]'` and our python `deep_merge` REPLACE arrays, not concatenate them. The example above shows what *should* be in the array; in practice the install script appends governance-pack entries to the existing arrays rather than blindly replacing. Run `install.sh --dry-run` and inspect the diff before approving.

---

## Case 3 — user already has `core-config` 3-hook bundle installed

### Before

```json
{
  "permissions": {
    "defaultMode": "plan",
    "deny": ["Read(./.env*)", "Read(./secrets/**)", "Bash(curl *)"]
  },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command",
          "command": "${HOME}/.claude/hooks/block-destructive.sh" }] },
      { "matcher": "Edit|Write",
        "hooks": [{ "type": "command",
          "command": "${HOME}/.claude/hooks/pre-edit-stash.sh" }] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write",
        "hooks": [{ "type": "command",
          "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/lint-touched.sh" }] }
    ]
  }
}
```

### After

```json
{
  "permissions": { /* deny extended; defaultMode unchanged */ },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${HOME}/.claude/hooks/block-destructive.sh" },
          { "type": "command", "command": "${HOME}/.claude/hooks/governance-pack/no-coauthor-trailer.sh" }
        ] },
      { "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "${HOME}/.claude/hooks/pre-edit-stash.sh" },
          { "type": "command", "command": "${HOME}/.claude/hooks/governance-pack/deny-prod-paths.sh" }
        ] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write|MultiEdit",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/lint-touched.sh" }] },
      { "matcher": ".*",
        "hooks": [{ "type": "command", "command": "${HOME}/.claude/hooks/governance-pack/telemetry.sh" }] }
    ],
    "Stop": [
      { "matcher": ".*",
        "hooks": [{ "type": "command", "command": "${HOME}/.claude/hooks/governance-pack/audit-gate.sh" }] }
    ]
  }
}
```

### What changed

- Same matcher slots: governance-pack appends its hook to the existing `hooks: [...]` list. Order: core-config runs first, governance-pack second.
- New matcher `.*` under `PostToolUse` for telemetry.
- New event `Stop` for audit-gate.
- `Edit|Write` upgraded to `Edit|Write|MultiEdit` (catches the `MultiEdit` tool too — added in Claude Code v2.1.x).

This is the **canonical merge result** and what the rest of this doc assumes for layered behavior.

---

## Case 4 — user has a heavily customized `settings.json`

If you have custom hooks, custom permission rules, or custom keys not in the template, the merge:

- **Preserves** every custom key not touched by the template (e.g. `apiKeyHelper`, `env`, `agent`, `companyAnnouncements`).
- **Layers** governance-pack hooks alongside yours in the same matcher (does not replace).
- **Adds** governance-pack deny rules to your existing `deny` array.
- Asks before each merge step. Use `--dry-run` to preview.

If anything goes wrong, the timestamped backup (`settings.json.bak.<ts>`) is your rollback path. `uninstall.sh` will offer to restore it interactively.

---

## How to verify the merge worked

```bash
# Check defaultMode
jq -r '.permissions.defaultMode' ~/.claude/settings.json
# → "plan"

# List all hooks wired
jq -r '.hooks | to_entries[] | "\(.key): \(.value | length) matcher(s)"' ~/.claude/settings.json

# Confirm governance-pack hooks are referenced
jq -r '.hooks | .. | .command? // empty' ~/.claude/settings.json | grep governance-pack
# → 4 lines: audit-gate, deny-prod-paths, no-coauthor-trailer, telemetry

# Confirm deny list contains the basics
jq -r '.permissions.deny[]' ~/.claude/settings.json | grep -E '\.env|secrets|curl'
```
