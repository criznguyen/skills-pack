# `fix-root-cause` — reject workarounds; fix root cause

When the agent considers a workaround — typographical evasion, error suppression, scope-narrowing escape, hardcoded sentinel value, skipped failing test — this skill triggers a four-question gate. A workaround ships ONLY if (1) there is documented time pressure AND (2) the workaround is comment-tagged in source AND (3) the follow-up is tracked with an owner and deadline AND (4) the reversibility plan is documented. Any NO answer rejects the workaround and sends the agent back to the root-cause path.

This README is the operator-facing onboarding. The agent-facing primer is [`SKILL.md`](SKILL.md); concrete bad-vs-good examples live in `prompts/anti-pattern-catalog.md`; the formal flowchart is in `prompts/decision-tree.md`.

## Quick start — no install action required

The skill is pure declarative knowledge. There is no hook, no settings.json edit, no daemon. Adoption is two steps:

1. `git pull` (or copy `core/fix-root-cause/` into your `~/.claude/skills/`).
2. The skill auto-attaches when the agent's prompt or its own output contains workaround-shaped trigger phrases ("workaround", "for now", "scoped to file X", "skip the test", "fallback to default", "2>/dev/null", "comment out the check", etc.) — see `SKILL.md` §"When to apply" for the full table.

That's it. The skill is read-only; it influences the agent's choice between root-cause-fix and workaround paths but emits no file writes itself.

## Why adopters benefit

| Pain point | What the skill changes |
|---|---|
| **"Sub-agents pass verify checks via prose tweaks instead of code changes"** | Sub-principle 1 (no typographical evasion) catches the rename-to-dodge-grep pattern explicitly; the catalog opens with the operator-caught underscore-evasion incident from ciscrm Wave 2 |
| **"Suppressed errors compound silently across releases"** | Sub-principle 2 (no error suppression without diagnosis) requires either a one-line WHY comment + follow-up tracker OR a specific known-non-fatal case named — blanket suppression is rejected |
| **"Agent ships partial fixes that look complete in PR review"** | Sub-principle 3 (no scope-narrowing escape) refuses silent scope drops; either expand scope, get an explicit narrowed scope from spec, or ship a partial fix WITH a follow-up issue |
| **"Hardcoded fallbacks hide misconfiguration until production"** | Sub-principle 4 (no hardcoded sentinel) requires either documented optional-default OR a loud failure on missing required config |
| **"`t.Skip()` accumulates with no path back to green"** | Sub-principle 5 (no skipping failing tests) requires explicit ticket + owner + deadline before any skip is accepted |
| **"How do I know when a workaround is truly OK?"** | The 4-question gate is exhaustive: time pressure AND comment AND tracker AND reversibility — all four. Three out of four sends the agent back to root cause |

The skill formalizes a discipline the operator has been enforcing informally via prompts and `AGENTS.md` for many months. The 2026-05-04 ciscrm Wave 2 underscore-evasion incident proved informal enforcement is insufficient — codification was the operator-mandated remediation.

## What the skill does NOT do

| Concern | Where it lives instead |
|---|---|
| Lint / AST scanning for `2>/dev/null` etc. in source | Future hook candidate; not v1.6.0 — the skill is rules-as-prompt, not hooks-as-enforcement |
| Pre-commit gate blocking workaround comments without a tracker entry | Future v1.6.x candidate if external adopter signal demands it; v1.6.0 is review-time guidance |
| Issue-tracker integration verifying tickets exist | Out of scope; the gate trusts the agent's claim that ISSUE-123 exists. Audit-time verification is the auditor's job |
| Refactoring suggestions (DRY, extract method) | `simplify` skill |
| Verifying whether a fact is in the codebase before claiming it | `core-config/anti-fantasy` rule |

## Compose with

- **`core-config`** — anti-fantasy is the sibling rule. Anti-fantasy: never claim a fact you haven't verified. fix-root-cause: never ship a fix that doesn't address the root cause. Both guard the same trust surface.
- **`audit`** — the pre-merge auditor uses `prompts/anti-pattern-catalog.md` as a PE-dimension checklist. Catch typographical evasion, suppressed errors, and silent scope narrowing before merge.
- **`delta-code-review`** — single-pass reviewer flags suppressed errors and `// WORKAROUND:` comments missing the required tracker entry. Cheaper than full audit; runs on every diff.
- **`governance-pack`** — the anti-pattern governance template (operator-side discipline document) inherits this skill's catalog as one of its enumerated anti-pattern surfaces.

## Files in this skill

| Path | Purpose | Lines |
|---|---|---|
| [`SKILL.md`](SKILL.md) | Front-matter + agent-facing skill body (5 sub-principles + 4-question gate) | ~210 |
| [`README.md`](README.md) | This file (operator-facing) | ~110 |
| [`prompts/decision-tree.md`](prompts/decision-tree.md) | 4-question gate as mermaid flowchart + plain-text fallback | ~120 |
| [`prompts/anti-pattern-catalog.md`](prompts/anti-pattern-catalog.md) | 12 bad-vs-good code examples with real session-debt references | ~280 |
| [`prompts/workaround-template.md`](prompts/workaround-template.md) | Standard `// WORKAROUND:` template + 5-question smell test | ~120 |
| [`tests/test-skill-shape.sh`](tests/test-skill-shape.sh) | Bash shape tests — front-matter, prompt files, catalog count, mermaid, template fields | ~140 |

## Tests

```bash
bash core/fix-root-cause/tests/test-skill-shape.sh
```

Verifies:

1. `SKILL.md` exists with valid front-matter (`name:` + `description:` keys present).
2. `README.md` exists and is non-empty.
3. All 3 prompt files exist under `prompts/` (decision-tree, anti-pattern-catalog, workaround-template).
4. Anti-pattern catalog has ≥12 entries (grep for entry markers).
5. Decision tree has mermaid syntax block.
6. Decision tree has a plain-text fallback section.
7. Workaround template has all 5 standard fields (Why root cause not fixed / Follow-up / Reversibility / Author / Date).
8. Front-matter `description:` field length is in the auto-attach quality envelope (200–900 chars).

Pass/fail summary: `PASS=N FAIL=0` → exit 0.

## Status

Shipped in claude-skills v1.6.0 (2026-05-04). Source: this commit. Trigger event: 2026-05-04 ciscrm Wave 2 sub-agent renamed a token in narrative prose to dodge a `grep -c` verify check rather than fix the underlying scope drift; operator caught it and mandated codification as a standalone skill.

Adoption signals to watch (90-day post-public-launch):

- 1+ external PR or issue referencing the 4-question gate as adopted in their project's review discipline.
- 0 operator complaints about trigger phrases over-firing on legitimate scope-narrowing or feature-flag work.
- 1+ revisit if a sixth recurring anti-pattern emerges (current 5 cover all observed incidents through 2026-05-04).

## Citation backbone

Operator's anti-lying-fix rule [Source: user MEMORY.md `feedback_zero_issues_golden_rule.md`]; SDLC strict discipline [Source: user MEMORY.md `feedback_follow_sdlc_strictly.md`]; underscore-evasion incident 2026-05-04 [Source: orchestrator pin, ciscrm Wave 2 — anonymized]; anti-fantasy sibling rule [Source: `core/core-config/SKILL.md`]; audit composition [Source: `core/audit/SKILL.md`].
