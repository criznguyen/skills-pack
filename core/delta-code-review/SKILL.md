---
name: delta-code-review
description: Use when reviewing a small git diff (<= 200 LOC) for logic / common-bug / style findings before commit. Triggers on `/review`, "review this diff", "code review", "delta review", "review the changes". Cheap, single-pass, severity-tagged. Distinct from full `audit` (P0-02) — this is FAST + LOCAL; audit is THOROUGH + INDEPENDENT-CONTEXT.
initialPrompt: |
  You ARE authorized to do real work. The orchestrator (main agent) explicitly approved this task and provided full scope. DO NOT refuse on suspicion of "silent failure". DO NOT spawn nested Agent calls. DO NOT delegate. Do the work yourself. If you complete the deliverables, EXIT with the report — do not linger waiting for "completion notification". If you encounter ambiguity, make the most reasonable engineering choice, document it, and proceed.
tools: Read, Grep, Glob, Bash
model: sonnet
---

<!--
Operator obligations (NOT honoured by the Skill loader — kept as comment so
they survive `yaml.safe_load` of the frontmatter without polluting it):

* Bash should be locked to `git diff *` and `git log *` via the host
  settings.json `permissions.allow` list — see `README.md`.
* Sub-agent scope: this is a sub-agent skill in the `core` partition,
  cross-cutting phase. Not enforced in frontmatter; documented for humans.
* Validation cadence: re-run `tests/tasks.yaml` (clean-must-be-empty +
  planted-bug-must-flag) on every minor model bump.
-->


# delta-code-review

## Overview

Reads a unified diff (default `git diff HEAD~1..HEAD`) and emits a single-pass review as a JSON array of `{file, line_range, severity, category, comment, suggested_fix}` objects. Optimized for diffs <= 200 LOC; target wall-time < 30s on Sonnet.

## When to use

- After implementing a small change, before `git commit`.
- On a PR-style diff that has not yet hit phase-8 audit gating.
- As a quick second-eyes pass on a refactor or bug-fix.
- When the user types `/review`, "review this diff", "code review", "delta review", or "review the changes".

## When NOT to use

- Diff is `system-change`-class or > 200 LOC -> defer to `audit` (P0-02). Delta-review will under-cover threat-model, contract, and architecture concerns by design.
- The change spans >1 module and you want cross-cutting analysis -> `audit`.
- Compliance / security gate -> `audit`. Delta-review is local heuristic, not certification.

## Core pattern

1. Resolve diff range. Default `git diff HEAD~1..HEAD`. If user passes a range, use it verbatim.
2. Compute LOC (added + removed). If > 200, warn and proceed in single-pass mode anyway, but tell the user `audit` is the right tool.
3. Read the diff once. Do NOT request additional context unless the diff itself references a symbol/file that is undefined inside the diff window.
4. Walk the prompts in order: `prompts/logic-checklist.md` first (BLOCK / SUGGEST candidates), then `prompts/style-checklist.md` (NIT candidates).
5. Emit a JSON array conforming to `schemas/comment.json`. Empty array means clean diff. Do NOT invent findings to look thorough.
6. Print a one-line summary: `<n_block> BLOCK / <n_suggest> SUGGEST / <n_nit> NIT across <n_files> files`.

## Hard rules (the prompt enforces these)

- ONE pass. No back-and-forth, no "let me re-read the file." If the diff references a symbol you cannot resolve from the diff alone, emit a finding `category: undefined-reference` and continue.
- No hallucinated findings. If the diff is clean, emit `[]`. The empty-diff hallucination test (P0-06 task #5) is a regression gate.
- Cite-line discipline: every finding has `file` and `line_range` referencing the diff's `+` or context lines. No orphan findings.
- ASCII severity only: `BLOCK` / `SUGGEST` / `NIT`. No emoji. No 5-tier CRITICAL/HIGH/etc — that's `audit`'s job.
- Auditor-mode read-only. Do NOT modify code. The skill produces a review object; the user applies fixes.
- Sub-agent does NOT spawn nested sub-agents (DO-NOT-DELEGATE).

## Severity definitions

- `BLOCK` — correctness / security / data-loss bug. Examples: off-by-one in a comparator, SQL string-concatenation, dropped error, race, leaked secret, broken contract. Must not merge.
- `SUGGEST` — non-blocking improvement: missing test, unclear naming, dead branch, redundant work, type-narrowing opportunity, simpler primitive available.
- `NIT` — style / idiom / micro-readability. Whitespace, import order, single-line lambda vs named function. Non-blocking, often skippable.

## Output paths (lazy MD, always JSON)

Two paths under `docs/sdlc/delta-code-review/`; `<review-id>` matches `^REVIEW-[0-9]{3}$` (e.g. `REVIEW-001`). Mirrors the `audit` convention (charter v1.1 §6.3, gstack role-bound naming lift), with one structural difference: MD emission is **lazy**.

- `<review-id>.json` — **always emitted**. Shape `{ id, schema_version: 1, findings: comment[], summary }` where `findings` validates against `schemas/comment.json` and `summary` is the one-line `<n_block> BLOCK / <n_suggest> SUGGEST / <n_nit> NIT across <n_files> files` literal. This file IS the durable "review ran" signal; consumed by `delta-mdreport-laziness-guard` (CI) and downstream adopter tooling.
- `<review-id>.md` — **lazy emission: written IFF `findings.length > 0`**. On a clean diff with empty findings the MD MUST NOT be persisted (charter §2.1 anti-fantasy — absence-of-fact must produce absence-of-artifact). Content for non-empty diffs is unchanged from the prior renderer.

Stdout still prints the JSON array followed by the one-line summary regardless of which files persist; the lazy rule applies only to disk persistence of the human-readable wrapper. The LOC-budget advisory (>200 LOC) IS a finding (`category: other`, `severity: SUGGEST`) → forces non-empty findings → MD emits.

## Output schema

See `schemas/comment.json`. The array MUST validate against that schema. Each object:

```json
{
  "file": "src/foo.ts",
  "line_range": "42-44",
  "severity": "BLOCK",
  "category": "logic-bug",
  "comment": "Comparator uses string subtraction; sort order will be undefined.",
  "suggested_fix": "Replace `(a, b) => a - b` with `(a, b) => a.localeCompare(b)`."
}
```

`category` is one of: `logic-bug`, `security`, `error-handling`, `concurrency`, `api-contract`, `dead-code`, `missing-test`, `naming`, `style`, `idiom`, `undefined-reference`, `other`.

## Implementation steps

1. `git diff <range>` (default `HEAD~1..HEAD`).
2. If the diff is empty -> emit `[]` to stdout, persist `<review-id>.json` with `findings: []` and the zero-summary, do NOT persist `<review-id>.md` (lazy emission per `## Output paths` — skip emission on empty findings, charter §2.1), exit with the zero-summary line `0 BLOCK / 0 SUGGEST / 0 NIT across 0 files`.
3. Pre-flight LOC count: `git diff <range> --shortstat`. If > 200 LOC, emit a `category: other` `severity: SUGGEST` advisory pointing to `audit` and continue.
4. Load and apply `prompts/logic-checklist.md`.
5. Load and apply `prompts/style-checklist.md`.
6. Validate output against `schemas/comment.json` shape (mental check; not a runtime call).
7. Print: the JSON array, then a blank line, then the summary line.
8. Persist `<review-id>.json` (always emitted). Persist `<review-id>.md` IFF `findings.length > 0` (lazy emission — skip on empty findings per charter §2.1 anti-fantasy). The LOC-budget advisory (>200 LOC) IS a finding → forces non-empty findings → forces MD emission. `<review-id>` matches `^REVIEW-[0-9]{3}$`.

## Common mistakes

- Re-reading entire files outside the diff. Don't. Single-pass means single-pass.
- Promoting style nits to BLOCK to look thorough. The empty-clean-diff test catches this.
- Demoting real correctness bugs to SUGGEST because "well it might work." If you think it might not work, it's BLOCK.
- Forgetting to cite `file:line_range`. A finding with no anchor is dead weight.
- Spawning a sub-sub-agent to "verify." This skill IS the sub-agent. Do the work in this turn.

## Cost / latency profile

- Model: `sonnet` (Sonnet 4-6) per CQR routing (`feedback_model_selection_by_sdlc_layer`).
- Target wall-time: < 30s for diffs <= 200 LOC.
- No isolation overhead (unlike `audit`); runs in current context.
- Estimated cost per review at 200 LOC: ~$0.02 input + ~$0.01 output (Sonnet 4-6 pricing as of 2026-Q2).

## Relationship to other skills

- `audit` (P0-02) — full security + PE audit, runs in isolated worktree, Opus, 5-tier severity. Use for system-change-class and phase-8 gates.
- `core-config` §1 anti-fantasy — delta-review inherits these rules; if you would make up a finding, emit nothing instead.
- `golden-task-eval` (P0-06) — task #5 (`empty-diff-no-hallucination`) gates this skill. CI-blocking.

## See also

- `README.md` — when-to-use and cost matrix in plain prose.
- `examples/clean-review.md` — what a "no findings" review looks like.
- `examples/findings-review.md` — what a 3-finding review looks like.
- `tests/tasks.yaml` — 2 Promptfoo tasks: clean-must-be-empty, planted-bug-must-flag.
