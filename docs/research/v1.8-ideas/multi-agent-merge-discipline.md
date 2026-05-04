# Skill idea — `multi-agent-merge-discipline`

**Origin**: 2026-05-04, ciscrm Wave 4.A.2 — 6 parallel sub-agents produced
~30min/merge × 4 sequential merges of orchestrator manual conflict
resolution on shared APPEND-ONLY files. Most conflicts were trivially
resolvable (additive blocks at adjacent locations) but blocked the
pipeline because git's textual merge couldn't recognize the blocks as
non-overlapping appends. Auto-generated files (sqlc gen, ctxq gen)
contributed ~80% of the conflict surface despite being 100% derivable.

## Problem statement

When N (typically 3–6) Opus sub-agents work in parallel worktrees from
the same base commit and each appends to shared infrastructure files,
the orchestrator pays an O(N) merge tax that scales worse than the
parallelism gain.

Observed conflict surface in ciscrm Wave 4.A.2 (1 PRE batch + 6 buckets):

| File class | Conflicts per merge | Why |
|---|---|---|
| `internal/platform/db/gen/*.sql.go` | 0 (per-table; non-overlap) | sqlc emits one file per query topic; agents on different topics |
| `internal/platform/db/gen/models.go` | 1 per merge | sqlc appends struct types alphabetically; adjacent additions diff-overlap |
| `internal/platform/db/gen/querier.go` | 2-3 per merge | sqlc appends interface methods alphabetically; many adjacencies |
| `internal/platform/db/ctxq/ctxq_gen.go` | 2-3 per merge | regenerated from gen/*.sql.go; same pattern |
| `internal/auth/rbac.go` | 1-2 per merge | role permission lists; agents add to same role |
| `internal/platform/http/handlers.go` | 1-2 per merge | Handlers struct field appends |
| `internal/platform/http/wave1_fg_handlers.go` | 1 per merge | route registration block appends |
| `cmd/api/cmd/main.go` | 2-3 per merge | imports + service constructor + handlers struct wiring |
| `audits/VERIFICATION-LEDGER.md` | 1 per merge | section appends (rare actual conflict; usually clean) |

Total per merge: 10-15 textual conflicts, ~80% on auto-generated files.

## Two-part fix

### Part A — Strip auto-generated files from sub-agent commits

**Premise**: auto-generated files are derivable from hand-written sources
(`db/queries/*.sql` → `internal/platform/db/gen/*` via `sqlc generate`,
then `internal/platform/db/ctxq/*` via `scripts/gen_ctxq.py`). Sub-agents
should never commit them; orchestrator regenerates AFTER each merge.

**Mechanism**: PreToolUse hook on `Bash` matching `git commit`:

1. Read project's `.claude/skills/multi-agent-merge-discipline/gen-paths.txt`
   (per-project allowlist — same shape as `governance-allow.txt`):
   ```
   internal/platform/db/gen/**
   internal/platform/db/ctxq/ctxq_gen.go
   ```
2. For each pattern, run `git reset HEAD -- <pattern>` to unstage matches.
3. Print summary: `[multi-agent-merge-discipline] stripped 7 auto-gen files
   from staging (will regen post-merge): internal/platform/db/gen/...`.
4. Continue with commit.

**Trade-off**: sub-agent's local build may fail if it needs the gen files
to verify. Solution: gen files exist on disk in the worktree (sub-agent
ran sqlc/ctxq during dev), they're just not staged. Build still works.

### Part B — Agent handoff manifest for shared APPEND-ONLY files

**Premise**: textual merge of additive blocks is wasteful when the
additions are structured (a permission entry, a route registration, a
struct field, an import). Sub-agents should declare WHAT they added in a
machine-readable manifest, and orchestrator merges PROGRAMMATICALLY.

**Mechanism**: each sub-agent emits `audits/manifests/<wave-id>-<bucket>.json`
as part of its commit:

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
    { "name": "Audiences", "type": "audience.Service", "comment": "Wave 4.A.6-MK-Audiences ..." }
  ],
  "main_imports": [
    "github.com/cis-crm/core/internal/marketing/audience"
  ],
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
  "ledger_entries": ["W4A6-AUDIENCES-1: ...", "W4A6-AUDIENCES-2: ..."]
}
```

**Orchestrator merge tool** (`scripts/merge-manifests.py` or similar):

```bash
# Take all manifest JSONs in audits/manifests/ + the base commit
# For each shared file, apply the structured additions:
#   - rbac.go: insert permission strings into role arrays alphabetically
#   - handlers.go: insert struct field declarations
#   - main.go: insert imports / service constructor lines / handler assignments
#   - VERIFICATION-LEDGER.md: append sections in wave-id order
# Emit a single merge commit with all changes applied.
```

**Trade-off**: requires upfront convention adoption + tooling.
**Benefit**: zero textual merge conflicts on shared files; merges become
mechanical and orchestrator-time drops from ~30min to ~5min per wave.

### Part C — Optional: pre-wave domain sharding

Long-term refactor: split shared files into per-domain shards so future
multi-agent waves don't touch the same file at all:

- `internal/auth/rbac/{core,marketing,parent,sales,events}.go` — each
  domain's role-permission additions live in its own file, merged in
  `rbac.go` via package-level `init()` slice append.
- `internal/platform/http/handlers/{core,marketing,parent,sales}.go` —
  Handlers struct uses embedded structs per domain.
- `cmd/api/cmd/wiring/{marketing,parent,sales}.go` — service wiring
  per domain, called from `Main()`.

This is a one-time refactor. After it ships, sub-agents on different
domains will literally not touch the same file, so 0 textual conflicts.

## Skill structure (proposed for v1.8)

```
core/multi-agent-merge-discipline/
├── SKILL.md              # how-to + rationale
├── README.md             # short
├── CLAUDE.md             # 1-line invocation hint
├── hooks/
│   └── pre-commit-strip-gen.sh   # Part A
├── templates/
│   ├── manifest.json.template    # Part B reference shape
│   └── merge-manifests.py        # Part B orchestrator merge tool
├── tests/
│   ├── pre-commit-strip-gen.test.sh
│   └── merge-manifests.test.py
└── examples/
    ├── ciscrm-wave-4.A.6-manifest.json   # real-world example
    └── ciscrm-wave-4.A.2-merge-tool.log  # before/after timing
```

## Adoption checklist for a project

1. Add `.claude/skills/multi-agent-merge-discipline/gen-paths.txt` listing
   auto-generated file globs.
2. Wire `pre-commit-strip-gen.sh` in `.claude/settings.json` PreToolUse
   `Bash` matcher when commit invoked.
3. Add `audits/manifests/` directory + `.gitignore` for nothing.
4. Document the manifest contract in project's `AGENTS.md` so sub-agent
   prompts reference it.
5. Add a `make merge-wave WAVE_ID=4.A.2` target wrapping the orchestrator
   merge tool.

## Non-goals

- Not a replacement for git merge — file-level adds/edits still go through
  normal merge. Only shared APPEND-ONLY files use the manifest.
- Not a code-formatter — agent's diffs are still reviewed by hand for
  semantic correctness; this skill only mechanizes the merge step.

## Estimated impact (Wave 4.A.2 retrospective)

- Manual merge time: 4 merges × ~25 min = 100 min
- With Part A only: ~10 min × 4 = 40 min (60% saving on gen-file conflicts)
- With Part A + Part B: ~5 min × 4 = 20 min + ~5 min tool prep = 25 min (75% saving)
- With Part C refactor (one-time): ~3 min × 4 = 12 min (88% saving going forward)

## Risk register

| Risk | Mitigation |
|---|---|
| Manifest schema drift across projects | Skill ships canonical schema + JSON Schema validator |
| Agent forgets to emit manifest | PreToolUse on commit checks for manifest presence; warns or blocks |
| Auto-gen-strip removes a hand-written file by mistake | Allowlist is project-specific; skill ships matcher precision tests |
| Merge tool produces invalid Go | Tool runs `gofmt + go build` on output; fails loudly if invalid |

## Linkage to existing skills

- Composes with `governance-pack` (per-project allowlist pattern is the
  same shape — reuse the loader).
- Composes with `audit-builtin` (manifest entries can become ledger
  entries automatically).
- Replaces ad-hoc `feedback_subagent_spawn_pattern` partial advice with a
  formal mechanism for the merge phase specifically.
