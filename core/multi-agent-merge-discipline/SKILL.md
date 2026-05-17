---
name: multi-agent-merge-discipline
description: Reduces orchestrator merge tax when N parallel sub-agents work in worktrees from a shared base. Two parts — (A) PreToolUse hook on `Bash` matching `git commit` strips per-project allowlisted auto-generated files (sqlc/ctxq/protobuf/etc.) from staging so orchestrator regenerates the union post-merge instead of resolving textual conflicts on derivable artifacts; (B) optional handoff-manifest convention so sub-agents declare structured additions (rbac perms, route mounts, struct fields, imports) in machine-readable JSON for programmatic merge of APPEND-ONLY shared files. Surfaces from ciscrm Wave 4.A.2 retro where 6 parallel agents produced ~30 min × 4 sequential merges of mostly-mechanical conflict resolution.
paths: []
when_to_use: Project-opt-in convention via `.claude/skills/multi-agent-merge-discipline/gen-paths.txt`; hook fires on `git commit` in repos that have configured it.
disable-model-invocation: true
type: governance
tools: Bash, Edit, Write
model: opus
blast_radius: repo-write
last-validated: 2026-05-04
---

# multi-agent-merge-discipline

When 3+ Opus sub-agents work in parallel worktrees from the same base
commit and each appends to shared infrastructure files (RBAC role
permissions, HTTP route registration, service wiring in `main`,
auto-generated DB query layer), git's textual merge can't recognize
non-overlapping additions as commutative. The orchestrator pays an O(N)
manual conflict-resolution tax that scales worse than the parallelism
gain.

This skill ships two complementary mechanisms:

## Part A — PreToolUse hook: strip auto-generated files from sub-agent commits

**File**: `hooks/pre-commit-strip-gen.sh` — installed globally to
`~/.claude/hooks/multi-agent-merge-discipline/pre-commit-strip-gen.sh`
by `core/governance-pack/install.sh` §18 and registered as a
PreToolUse `Bash` hook in `~/.claude/settings.json`. The hook is
opt-in per project: it silent no-ops when the project lacks
`<project>/.claude/skills/multi-agent-merge-discipline/gen-paths.txt`,
so the global registration is safe for projects that never adopt the
skill.

**Logic**:
1. Detect the tool call is `git commit` (heuristic: `command` starts with
   `git commit` or contains `git commit` after a `cd` / `&&`).
2. Read the project's `.claude/skills/multi-agent-merge-discipline/gen-paths.txt`
   (per-project allowlist — same shape as `governance-pack/governance-allow.txt`).
3. For each glob pattern, run `git reset HEAD -- <pattern>` to unstage
   matching files.
4. Print summary on stderr:
   `[multi-agent-merge-discipline] stripped N auto-gen files from staging
   (will regen post-merge): <list>`.
5. Exit 0 — commit proceeds with stripped files reverting to working-
   tree-only state. They still exist on disk; just not in this commit.

**Effect**: sub-agent's commit contains only hand-written sources
(`db/queries/*.sql`, service code, handlers). Auto-generated artifacts
(`internal/platform/db/gen/*.go`, `ctxq_gen.go`, generated proto/grpc
stubs, OpenAPI clients, etc.) are excluded. Orchestrator regenerates
them via the canonical `make generate` (or equivalent) AFTER each merge,
producing the union of all sub-agents' query additions.

**Project setup**:

```
.claude/skills/multi-agent-merge-discipline/gen-paths.txt
```

Example for a Go + sqlc project:

```
internal/platform/db/gen/**
internal/platform/db/ctxq/ctxq_gen.go
```

Example for a TypeScript + OpenAPI project:

```
src/generated/**
api/types.gen.ts
```

`~/.claude/settings.json` PreToolUse matcher (auto-registered by
`core/governance-pack/install.sh` §18):

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "${HOME}/.claude/hooks/multi-agent-merge-discipline/pre-commit-strip-gen.sh",
      "timeout": 5000
    }
  ]
}
```

The path is `${HOME}/...` (NOT `${CLAUDE_PROJECT_DIR}/...`) so the
hook resolves on every Bash invocation regardless of cwd. Projects
opt in by creating `gen-paths.txt`; the hook silent no-ops when the
allowlist is absent.

## Part B — Agent handoff manifest

Each sub-agent emits `audits/manifests/<wave-id>-<bucket>.json` as the
LAST artifact of its commit (or in a follow-up commit on the same
branch). The manifest declares structured additions to shared
APPEND-ONLY files in machine-readable form:

```json
{
  "wave_id": "4.A.6",
  "bucket": "MK-Audiences",
  "agent_id": "a0a04bf281d93e383",
  "base_commit": "2f2c0a9",
  "rbac_appends": [
    { "role": "RoleHeadOfSchool", "permissions": ["marketing.audiences.read"] },
    { "role": "RoleMarketingOfficer", "permissions": ["marketing.audiences.read", "marketing.audiences.write", "marketing.audiences.delete", "marketing.audiences.refresh"] }
  ],
  "handlers_struct_fields": [
    { "name": "Audiences", "type": "audience.Service", "comment": "Wave 4.A.6 ..." }
  ],
  "main_imports": ["github.com/cis-crm/core/internal/marketing/audience"],
  "main_service_wiring": [
    { "var": "audienceSvc", "expr": "audience.NewService(queries, pool, auditLogger)" }
  ],
  "main_handlers_assignments": [
    { "field": "Audiences", "value": "audienceSvc" }
  ],
  "routes": [
    { "mount_func": "marketingRoutes", "router_call": "audienceRoutes(r, h)" }
  ],
  "ledger_section": "## Wave 4.A.6-MK-Audiences",
  "ledger_entries": ["W4A6-AUDIENCES-1: ..."]
}
```

**Orchestrator merge tool**: `templates/merge-manifests.py`. Takes:
- All manifest files in `audits/manifests/`
- The shared file set (project-specific paths)

Emits a single merge commit applying every manifest's additions in
deterministic order (alphabetical by `wave_id`+`bucket`).

**Schema validation**: `templates/manifest.schema.json` — JSON Schema
that sub-agents and orchestrator both validate against.

## When to use

Use this skill when:
- Project regularly runs 3+ parallel Opus sub-agents per wave.
- Sub-agents append to a small set of shared files (RBAC, routes, wiring).
- Auto-generated files dominate the conflict surface.

DO NOT use when:
- Single-agent or sequential workflow (no parallel runtime to gain).
- Shared files already shard per-domain (e.g.
  `internal/auth/rbac/{marketing,parent,sales}.go` — each domain owns
  its file → no textual conflicts).
- Orchestrator merge time < 5 min/wave (overhead of manifest convention
  exceeds savings).

## Adoption checklist

1. **Install the global hook** — run `bash core/governance-pack/install.sh`
   from the claude-skills checkout. §18 copies the hook to
   `~/.claude/hooks/multi-agent-merge-discipline/pre-commit-strip-gen.sh`
   and registers the PreToolUse(`Bash`) entry. Idempotent + drift-recovery
   safe (rewrites legacy `${CLAUDE_PROJECT_DIR}/...` registrations).
2. **Project opt-in** — author
   `<project>/.claude/skills/multi-agent-merge-discipline/gen-paths.txt`
   listing your project's auto-generated globs (one per line). The hook
   silent no-ops on every project that lacks this file, so step 1 is
   safe to run globally.
3. (Optional Part B) Author `audits/manifests/` directory.
4. (Optional Part B) Update sub-agent prompts to emit manifest JSON
   alongside their commit.
5. (Optional Part B) Add `make merge-wave WAVE_ID=...` target wrapping
   the merge tool.
6. Document the convention in your project's `AGENTS.md` so future
   sub-agents know to honor it.

## Risk register

| Risk | Mitigation |
|---|---|
| `gen-paths.txt` glob matches a hand-written file | Skill ships matcher precision tests; project owns the allowlist |
| Sub-agent's local build fails before commit because gen files were stripped from STAGED set | Files still on disk in worktree → build still works. Strip is staging-only |
| Orchestrator forgets to regen after merge | Project `Makefile` enforces `make generate` as part of `make verify` |
| Manifest schema drift between projects | Skill ships canonical JSON Schema; validator in tool |

## Verify gates

```bash
# Part A: strip activates only on git commit
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"}}' | \
  hooks/pre-commit-strip-gen.sh
# expected: stderr "[multi-agent-merge-discipline] stripped..." or "no auto-gen paths matched"

# Part A: doesn't activate on unrelated bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | \
  hooks/pre-commit-strip-gen.sh
# expected: silent exit 0
```

## Related

- Composes with `governance-pack` (per-project allowlist pattern).
- Composes with `audit-builtin` (manifest entries → ledger entries).
- Origin doc: `docs/research/v1.8-ideas/multi-agent-merge-discipline.md`.
