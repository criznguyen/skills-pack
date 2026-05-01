# Anti-patterns template — governance-class skills only

> *Only canonical anti-pattern template. Do not duplicate into per-skill
> `templates/` directories. Sourced as a pattern adopt from
> `mattpocock/skills/engineering/tdd/SKILL.md:19-41` (MIT — see `NOTICES.md`).
> Heading shape only; content discipline below is ours.*

## Purpose

Governance-class skills (`core/audit/`, `core/governance-pack/`,
`core/delta-code-review/`) inherit charter v1.1 §2.5 verifiability — the
reader must learn headline failure modes in <2 minutes. This template
defines the canonical `## Anti-patterns` section shape used in those
skills' `SKILL.md` (or `README.md`, whichever the skill convention selects).

## Governance-class only

This template applies ONLY to skills under:

- `core/audit/`
- `core/governance-pack/`
- `core/delta-code-review/`

It does NOT apply to `opinions/` (any subdirectory), other domain-specific
skills under `core/` (e.g. `core/core-config/`, `core/worktree-spawn/`,
`## Anti-patterns` into a non-governance-class skill trigger a CI warning
from `anti-pattern-template-guard`. Solo-engineer-style failure modes
belong in README "Risks" tables or `lessons.md` instead.

## Required fields per AP entry

Each `### AP-N: <headline>` entry MUST carry the two anchored fields below
as the **first two body lines**, in order:

1. `**Charter §-anchor**: §X.Y "<verbatim quote of the clause>"`
2. `**Gate state**: BLOCK | WARN | INFO`

Both are grep-able by literal-string match (`grep -F`). The CI guard
requires both within 6 lines of each `### AP-` heading.

`Gate state` values:

- **BLOCK** — a `[machine]` gate catches it pre-merge; cannot be bypassed
  without a `system-change:` PR.
- **WARN** — a `[machine]` gate emits a PR Annotations warning but does
  not block merge; reviewer attention is the second line of defense.
- **INFO** — no gate catches it directly; the entry exists so readers can
  name the failure mode (Phase 6 decisions.md or audit findings prose can
  cite the AP-N tag).

After the two required fields, the entry MUST carry three prose lines:

3. `**Description**: 1-3 sentences naming the failure mode and why it
   matters in this skill.`
4. `**Symptom**: 1 sentence — what an operator sees when it occurs.`
5. `**Mitigation**: 1-2 sentences — what this skill does about it.`

## Cap

A governance-class skill MUST emit **max 5 AP entries** (`### AP-1`
through `### AP-5`) — at most five, no exceptions. CI warns at count ≥6.
Heading inflation is the primary loss mode (final-apply-matrix v2
C5-F4); five slots forces prioritization. Raising the cap requires a
`system-change:` PR.

## Forbidden patterns

- **WRONG/RIGHT code blocks** — the mattpocock `tdd:19-41` source uses
  these for solo-engineer test correctness. Forbidden here. Governance-
  class failure modes are prose + charter-§ anchor + gate-state; they do
  not fit code diffs without losing the anchor signal (Finding 4).
- **Severity scales other than BLOCK/WARN/INFO** — CRITICAL/HIGH/MEDIUM/
  LOW are auditor-finding severities (different axis). Gate state is
  about the catch mechanism, not blast-radius.
- **AP-N tags reused across skills** — `AP-1` in `core/audit/` is
  unrelated to `AP-1` in `core/delta-code-review/`. Tags local to skill.

## Worked example (copy-paste starting point)

The example would live in a hypothetical `core/audit/SKILL.md` under
`## Anti-patterns`. (Retrofit is OUT of scope for THIS PR.)

```markdown
## Anti-patterns

### AP-1: Severity laundering — CRITICAL findings reframed as "out of scope"

- **Charter §-anchor**: §6 "Zero-deferral on CRITICAL or HIGH"
- **Gate state**: BLOCK
- **Description**: The auditor recognizes a CRITICAL or HIGH finding but
  reframes it as "out of scope" or "tracked separately" to avoid the
  zero-deferral rule. Charter §6 forbids this; audit-builtin smoke
  enforces via schema-level severity validation.
- **Symptom**: A finding's `severity: HIGH` appears alongside body prose
  containing "out of scope", "tracked in follow-up", or "deferred".
- **Mitigation**: Auditor Phase 8 self-check greps emitted `findings.json`
  for severity ≥ HIGH paired with deferral language; smoke fails build
  on any match.
```

## Adoption checklist

- [ ] Section heading exactly `## Anti-patterns` (no suffix, no colon).
- [ ] Each entry `### AP-N: <headline>` (N starts at 1).
- [ ] Entry's first body line `**Charter §-anchor**: §X.Y "..."`.
- [ ] Entry's second body line `**Gate state**: BLOCK | WARN | INFO`.
- [ ] Entry count ≤ 5.
- [ ] No WRONG/RIGHT code blocks anywhere in the section.
- [ ] `anti-pattern-template-guard` passes with zero warnings.

## CI guard

runs every PR. **Warn-only in v1.2**; the v1.2 follow-up retrofit PR
flips to error mode after the three governance-class skills have all
landed conformant `## Anti-patterns` sections.

## Source attribution

Heading shape: pattern adopt from
`mattpocock/skills/engineering/tdd/SKILL.md:19-41` (MIT). Content
discipline (required fields, ≤5 cap, scoping, WRONG/RIGHT prohibition)
is ours. See `NOTICES.md` for full MIT attribution.
