# delta-code-review

A cheap, single-pass review skill for small diffs. Distinct from full `audit` (P0-02): delta-review is **fast and local**; audit is **thorough and independent-context**.

## What this skill does

Reads `git diff HEAD~1..HEAD` (or any range you pass) and emits a JSON array of findings shaped per `schemas/comment.json`. Each finding has a file, a line range, a severity (`BLOCK` / `SUGGEST` / `NIT`), a category, a comment, and a concrete suggested fix.

## When to use

- Right after implementation, before `git commit`.
- On a PR-style diff that has not yet hit phase-8 audit gating.
- As a quick second-eyes pass on a refactor or bug-fix.
- The skill auto-invokes on `/review`, "review this diff", "code review", "delta review", "review the changes". You can also invoke it manually.

## When NOT to use — defer to `audit`

- Diff is `system-change`-class.
- Diff is > 200 LOC.
- The change spans more than one module and you want cross-cutting analysis.
- This is a security / compliance gate.

In those cases, run `audit` (P0-02) instead. Delta-review will under-cover threat modeling, contract analysis, and architecture concerns by design.

## Cost / latency profile

| Dimension | Delta-code-review (this skill) | Audit (P0-02) |
| --- | --- | --- |
| Model | `sonnet` (Sonnet 4-6) | `opus` (Opus 4-7) |
| Context | shared with main session | isolated worktree, fresh sub-agent |
| Tools | `Read`, `Grep`, `Glob`, `Bash(git diff)` | same + threat-model loaded |
| Severity scale | 3-tier: `BLOCK` / `SUGGEST` / `NIT` | 5-tier: `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO` |
| Target diff size | <= 200 LOC | up to 500 LOC |
| Wall-time target | **< 30s** | < 5 min |
| Estimated cost (200 LOC) | ~$0.03 | ~$0.40 |
| Modifies code | never | never |
| Spawns sub-agents | never | yes (via `safe-spawn-claude.sh`) |
| Triggers | `/review`, "review this diff" | manual gate at phase-8 |

The two skills are complementary, not redundant. Run delta-review on every commit-sized change; run audit at phase-8 / phase-9 gates and on system-change-class work.

## Severity scale (delta-review uses 3 tiers, not 5)

- **BLOCK** — correctness / security / data-loss / contract-break. Must not merge.
- **SUGGEST** — non-blocking improvement (missing test, dead branch, type-narrowing, simpler primitive).
- **NIT** — style / idiom / micro-readability. Skippable.

Why 3 tiers instead of `audit`'s 5? Delta-review optimizes for speed and signal-to-noise on a small diff. Distinguishing CRITICAL from HIGH requires threat-model context the skill does not load. If you need that distinction, run `audit`.

## Output shape

```json
[
  {
    "file": "src/sort.ts",
    "line_range": "42-44",
    "severity": "BLOCK",
    "category": "logic-bug",
    "comment": "Comparator uses string subtraction; sort order will be undefined.",
    "suggested_fix": "Replace `(a, b) => a - b` with `(a, b) => a.localeCompare(b)`."
  }
]
```

Followed by a one-line summary: `1 BLOCK / 0 SUGGEST / 0 NIT across 1 files`.

Empty array means clean diff. The skill does NOT invent findings to look thorough — that behavior is regression-tested.

## Hard rules

- **ONE pass.** No back-and-forth. No "let me re-read." If the diff references something undefined inside the diff window, emit `category: undefined-reference` and continue.
- **Cite-line discipline.** Every finding has a `file` and `line_range`. No orphan findings.
- **No nested sub-agents.** Do the work in this turn.
- **Read-only.** The skill produces a review object; the user applies fixes.

## Files in this skill

```
core/delta-code-review/
  SKILL.md                          # the skill definition + hard rules
  prompts/
    review.md                       # the primary single-pass prompt
    logic-checklist.md              # BLOCK / SUGGEST candidates
    style-checklist.md              # NIT candidates
  schemas/
    comment.json                    # JSON schema for the output array
  examples/
    clean-review.md                 # what `[]` + zero-summary looks like
    findings-review.md              # what 1 BLOCK + 1 SUGGEST + 1 NIT looks like
  tests/
    tasks.yaml                      # 2 Promptfoo tasks (clean + planted-bug)
    fixtures/
      clean.diff                    # ~50 LOC clean diff fixture
      planted-bug.diff              # ~150 LOC diff with off-by-one comparator
  README.md                         # this file
```

## Tests

`tests/tasks.yaml` ships two Promptfoo-shaped tasks:

1. **`clean-no-findings`** — fixture: `tests/fixtures/clean.diff`. Asserts the output is `[]` and the summary is all-zeros. Catches false-positive hallucination.
2. **`planted-bug-flagged`** — fixture: `tests/fixtures/planted-bug.diff`. Asserts at least one finding with `severity: BLOCK` and `category: logic-bug` referencing the planted off-by-one / `a - b` comparator on strings. Catches under-coverage of the BLOCK tier.

Both tasks run via the project-wide `golden-task-eval` (P0-06). Grader pinned to `claude-haiku-4-5-20251001`, temperature 0, N=3, >= 2/3 must pass per the eval-skeleton SLO.

## Migration: lazy MD emission (v1.2)

**What changed (v1.2 #6, mattpocock-track):** the skill emits `<review-id>.md` ONLY when findings is non-empty. On clean diff (`findings == []`), MD is NOT written — only `<review-id>.json` persists. charter §2.1 anti-fantasy: absence-of-fact must produce absence-of-artifact; a placeholder MD on a clean PR was the canonical fantasy-of-progress example.

**JSON path and shape (always emitted):**

- Shape: `{ id: string, schema_version: 1, findings: comment[], summary: "<n_block> BLOCK / <n_suggest> SUGGEST / <n_nit> NIT across <n_files> files" }`. The `findings` array validates against `schemas/comment.json`; `summary` is the same one-line literal printed to stdout.

**Migration recipe** for downstream CI consumers that previously checked MD existence:

```bash
# OLD (breaks on v1.2+ clean PRs — MD no longer emitted on empty findings):

# NEW — assert "review ran" via JSON existence + shape:
```

Detect a clean review: `jq -e '.findings | length == 0' <id>.json`. Gate on BLOCK: `jq -e '[.findings[].severity] | index("BLOCK")' <id>.json`.


## Related skills

- `audit` (P0-02) — full security + PE audit, isolated context, 5-tier severity.
- `bug-fix-with-failing-test` (P1-08) — when delta-review surfaces a BLOCK, this is how you remediate.
- `bounded-refactor` (P1-09) — keep refactor diffs small enough that delta-review remains useful.
- `golden-task-eval` (P0-06) — runs this skill's regression tests in CI.
