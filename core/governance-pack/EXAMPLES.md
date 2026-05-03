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

---

## Case 5 — per-project allowlist (v1.4.3+)

The v1.4.2 universal denylist (`**/auth/**`, `**/migrations/**`,
`**/billing/**`, etc.) protects every project but over-fires when a project
enters surge work IN those paths. v1.4.3 adds a per-project allowlist
(`<project>/.claude/governance-allow.txt`) that wins over the universal
denylist for THAT PROJECT ONLY, with full JSONL audit trail.

### Setup

```bash
# project root has .git/, so the hook's auto-detection finds it
cd <project-root>
mkdir -p .claude

# add patterns to allowlist (same glob format as prod-paths.txt)
# v1.4.4: patterns must start with **/ — they match ABSOLUTE paths.
cat > .claude/governance-allow.txt <<'EOF'
# audit-remediation 2026-05-03 — closing 14 FAIL findings
# REMOVE THIS FILE AFTER REMEDIATION COMMIT LANDS
**/internal/auth/**
**/db/migrations/**
EOF
```

### Pattern format gotcha (v1.4.4)

Patterns are matched against ABSOLUTE paths. Bare `internal/auth/**` does NOT
match `/home/.../internal/auth/foo.go` — it must be `**/internal/auth/**`.
v1.4.4 hooks emit a HINT line on the deny stderr if an allow-file is present
but no pattern matched; that's almost always the missing `**/` prefix.

### Verify the hook allows + audit-logs

Trigger an `Edit` on a path matching the allowlist. The PreToolUse hook chain
fires; `deny-prod-paths.sh` walks up to find `.git/`, reads
`.claude/governance-allow.txt`, matches the pattern, exits 0, and appends a
JSONL line:

```bash
# manual smoke-test (mimics what Claude's Edit tool emits to stdin):
echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$PWD"'/internal/auth/middleware.go"}}' \
  | bash ~/.claude/hooks/governance-pack/deny-prod-paths.sh
echo "exit=$?"
# → exit=0 (allowed)
```

### Inspect the audit log

```bash
cat .claude/state/governance-allow.jsonl | jq .
```

Each entry includes the timestamp, tool name, file path, the matched glob
pattern, and the allow-file source — sufficient for a reviewer to
post-hoc-validate that sensitive-path edits during the surge were intentional
and within the agreed allowlist scope.

```json
{
  "ts": "2026-05-03T13:09:25Z",
  "tool": "Edit",
  "file_path": "/home/criznguyen/projects/ciscrm/internal/auth/middleware.go",
  "matched_pattern": "**/internal/auth/**",
  "allow_file": "/home/criznguyen/projects/ciscrm/.claude/governance-allow.txt",
  "reason": "governance-allow match"
}
```

### Tear-down

After remediation lands and the audit cycle re-passes, remove the allowlist
file (the universal denylist resumes automatically — no global state change):

```bash
rm .claude/governance-allow.txt
```

The audit log (`.claude/state/governance-allow.jsonl`) is preserved for
review; either commit it or wipe per your repo policy.

### Negative-case sanity check

Without the allowlist file present, the same Edit attempt is blocked:

```bash
rm -f .claude/governance-allow.txt
echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$PWD"'/internal/auth/middleware.go"}}' \
  | bash ~/.claude/hooks/governance-pack/deny-prod-paths.sh
echo "exit=$?"
# → exit=2 (BLOCKED — matched pattern: **/auth/**)
```
