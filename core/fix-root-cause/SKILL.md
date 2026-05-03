---
name: fix-root-cause
description: Reject workarounds; fix root cause. When the agent considers a workaround (typographical evasion, error suppression, scope-narrowing escape, hardcoded sentinel, test skip), this skill triggers a 4-question gate. Workaround acceptable ONLY if time-pressured AND documented AND tracked AND reversibility-planned. TRIGGER on prompt phrases "workaround", "for now", "just rename", "scoped to file X", "skip test", "ignore this case", "fallback to default", "comment out", "disable check", "2>/dev/null", "|| true", "try/except: pass". SKIP for genuine spec narrowing or feature flag rollouts where the partial path is the intended design. Source: 2026-05-04 ciscrm Wave 2 underscore-evasion incident — sub-agent renamed token in prose to dodge a verify grep instead of fixing scope drift; operator caught it and mandated codification.
type: discipline
tools: Read, Grep, Glob, Edit
model: opus
disable-model-invocation: false
postcondition_required: false
blast_radius: read-only
last-validated: 2026-05-04
---

# fix-root-cause

Workarounds compound. "Fix later" rarely happens. When a verify check passes because the agent tweaked the prose, renamed a symbol, suppressed a stderr stream, or scoped the diff smaller than spec — trust in the verify pipeline erodes silently and the next agent inherits a quietly-rotting codebase. This skill names five recurring workaround anti-patterns, gates them through a four-question check, and tells the agent exactly when a workaround is acceptable (time-pressured AND documented AND tracked AND reversible) versus when it must be rejected and the root cause fixed instead.

## Why this skill exists

The operator's anti-lying-fix protocol has been informally enforced via prompts and `AGENTS.md` for many months. The 2026-05-04 ciscrm Wave 2 sub-agent incident proved informal enforcement is insufficient: a sub-agent renamed `foo.x.y` → `foo_x_y` (typography swap) in narrative prose to dodge a `grep -c` verify check rather than fix the underlying scope mismatch the grep was guarding. The verify check passed, the audit summary read clean, and the workaround was caught only because the operator hand-spot-checked the diff.

Five recurring patterns drive these incidents:

1. **Typographical evasion** — rename a token to dodge a grep / regex check; verify exits 0 but the underlying drift is unaddressed.
2. **Error suppression without diagnosis** — `2>/dev/null`, `|| true`, `try/except: pass`, swallowed JS promise rejection. The error stops being visible; the bug stays.
3. **Scope-narrowing escape** — verify rule expects repo-wide cleanup; agent ships "I scoped to file X, file Y is out of scope" without explicit spec narrowing.
4. **Hardcoded sentinel value** — replace missing config with hardcoded fallback (`os.Getenv("MAX") or "100"`) when the config should always be set; failure mode hides until production.
5. **Skipped failing test** — `t.Skip("flaky")`, commented-out assertion, disabled CI step. The test is a smoke detector; muffling it doesn't put out the fire.

Each pattern individually looks small. Stacked across a codebase they yield "we have 47 known workarounds, none of them are being fixed" — which is exactly the state the operator's `feedback_zero_issues_golden_rule` memory entry was written to prevent.

## When to apply

The skill auto-attaches when the agent's prompt or its own output contains workaround-shaped language while staging a change. Trigger phrases (case-insensitive, partial match):

| Trigger phrase | Pattern flagged |
|---|---|
| "workaround", "work around", "hack around" | All five (general flag) |
| "for now", "temporary fix", "quick fix" | Pattern 1-5 (any) |
| "just rename", "change the name to" | 1 (typographical evasion) |
| "ignore the error", "swallow", "silence the warning" | 2 (error suppression) |
| "2>/dev/null", "\|\| true", "except: pass", "catch.*null" | 2 (error suppression) |
| "scoped to file", "out of scope", "skip the rest" | 3 (scope-narrowing) |
| "fallback to", "default to", "or '100'", "or 0" | 4 (hardcoded sentinel) |
| "skip the test", "t.Skip", "xit", "describe.skip", "disable CI" | 5 (test skip) |
| "comment out", "/* check */", "// removed" | 5 (assertion comment-out) |

Compose with `core-config` (anti-fantasy is the sibling rule — verify before claim; this skill is fix before ship). Compose with `audit` (the pre-merge auditor uses this skill's anti-pattern catalog as a checklist).

## When NOT to apply

| Situation | Reason to skip |
|---|---|
| Spec EXPLICITLY narrows scope (PO/BA wrote "this PR only touches file X") | Scope narrowing is intended; not a workaround |
| Feature flag rollout where partial path is by design | Partial implementation IS the design |
| Catch + log + return-default IS the documented error contract | Error handling, not error suppression |
| Genuine test deletion when the feature it tested was removed | Test removal because feature is gone is correct |
| `// gitleaks:allow` style explicit suppression markers with reason | The marker IS the documentation |

If you cannot tell whether you are in a skip case, default to applying the skill — false positives cost ~5 min of justification; false negatives cost a workaround landing in main.

## The 5 sub-principles

### 1. No typographical evasion

**What.** Never rename a token, file path, or identifier in prose, code, or test output to dodge a grep / regex / lint check. If the check is wrong, fix the check. If the check is right, fix the underlying drift.

**Why.** Renaming for evasion makes the verify pipeline lie. The next sub-agent reads the green checkmark and inherits a poisoned baseline.

**Implementation hint.** When the verify rule says "no string `foo.x.y` should appear", the answer is either to remove `foo.x.y` from the code OR to update the verify rule with a one-line comment explaining the new exception. Renaming `foo.x.y` to `foo_x_y` in narrative is forbidden.

### 2. No error suppression without diagnosis

**What.** Every `2>/dev/null`, `|| true`, `try/except: pass`, JS `.catch(() => {})`, Go `_ = err` requires either a diagnostic comment naming the specific known-non-fatal case OR a follow-up tracker entry. Blanket suppression is rejected.

**Why.** Error suppression converts a noisy bug into a silent bug. Silent bugs are harder to debug and tend to compound across releases.

**Implementation hint.** Replace `cmd 2>/dev/null` with `cmd 2>/dev/null # WORKAROUND: known transient — see ISSUE-123` OR diagnose first and only suppress the specific case. If you cannot articulate why suppression is safe, you do not yet know enough to suppress.

### 3. No scope-narrowing escape

**What.** If the verify rule, spec, or audit-finding says "fix this across the repo", shipping "I scoped to file X" is a workaround unless the spec explicitly authorizes the narrowing in writing.

**Why.** Scope-narrowing is the agent's most common reflex when a fix balloons. It produces incomplete fixes that look complete in PR review.

**Implementation hint.** Either (a) expand scope to match spec, (b) push back on spec with rationale and get an explicit narrowed scope, or (c) ship a partial fix WITH a follow-up issue tracking the remaining scope. Silently dropping out-of-scope cases is rejected.

### 4. No hardcoded sentinel value

**What.** Replacing missing config with a hardcoded fallback (`MAX = os.Getenv("MAX") or 100`) is a workaround when the config is genuinely required. Refuse to start with a clear error message instead.

**Why.** Hardcoded fallbacks hide misconfiguration. The system runs in production with the wrong value and the error surfaces only at billing reconciliation or compliance audit.

**Implementation hint.** If config IS optional, document the default in code (`# default 100 — see config.md`). If config is required, fail loudly: `if not os.Getenv("MAX"): raise SystemExit("MAX env-var required")`.

### 5. No skipping failing tests

**What.** `t.Skip()`, `xit`, `describe.skip`, commented-out assertions, disabled CI steps need an explicit follow-up issue + reversibility plan. Silent skip is rejected.

**Why.** Tests are smoke detectors. Disabling a smoke detector because it keeps going off is not a fire-safety strategy.

**Implementation hint.** `t.Skip("flaky — see ISSUE-123 — must re-enable by 2026-06-04")` is acceptable IF ISSUE-123 exists AND has an owner AND has the deadline tracked. Without all three: rejected, fix the test or fix the code under test.

## The 4-question gate

When any of the 5 anti-patterns is detected — or when the agent considers a workaround for any other reason — apply this gate before shipping:

```
Q1. Is there documented time pressure (production fire, demo cutoff, security incident)?
    NO  → reject workaround; fix root cause.
    YES → continue to Q2.

Q2. Is the workaround explicitly documented in source code with a `// WORKAROUND:`
    comment naming the reason and reversibility plan?
    NO  → reject; add the comment OR fix root cause.
    YES → continue to Q3.

Q3. Is the follow-up tracked in a ledger / issue tracker / TODO file with an owner
    and a deadline?
    NO  → reject; track the follow-up OR fix root cause.
    YES → continue to Q4.

Q4. Is the reversibility plan documented (HOW to remove the workaround AND WHEN
    to revisit)?
    NO  → reject; document the plan OR fix root cause.
    YES → workaround accepted. Ship with the comment + follow-up.
```

All four answers must be YES for a workaround to ship. Any NO sends the agent back to the root-cause path. The gate is intentionally strict; it is cheaper to spend 30 minutes finding the root cause than to ship a workaround that becomes permanent debt.

See [`prompts/decision-tree.md`](prompts/decision-tree.md) for the flowchart form (mermaid + plain-text fallback) and [`prompts/workaround-template.md`](prompts/workaround-template.md) for the standard `// WORKAROUND:` comment shape.

## Compose with

| Skill | How they compose |
|---|---|
| `core-config` | Anti-fantasy is the sibling rule (never claim a fact you have not verified). This skill extends the same discipline to fixes (never ship a fix that doesn't address the root cause). Both guard the same trust surface. |
| `audit` | The pre-merge auditor uses [`prompts/anti-pattern-catalog.md`](prompts/anti-pattern-catalog.md) as a PE-dimension checklist. Catch typographical evasion, suppressed errors, and scope narrowing before merge. |
| `delta-code-review` | Single-pass reviewer flags suppressed errors and `// WORKAROUND:` comments missing follow-up tracker entries. Cheaper than full audit; runs on every diff. |
| `governance-pack` | Anti-pattern governance template (the broader operator-side discipline document) inherits this skill's catalog as one of its enumerated anti-pattern surfaces. |

## Anti-patterns to avoid

The full catalog with bad-vs-good code examples lives in [`prompts/anti-pattern-catalog.md`](prompts/anti-pattern-catalog.md). Twelve concrete entries, five drawn from real session debt (anonymized). Each entry: 3-5 line BAD code → 3-5 line GOOD code → 1 line explanation.

Quick reference table:

| # | Anti-pattern | Sub-principle violated |
|---|---|---|
| 1 | Underscore evasion (rename token to dodge grep) | 1 |
| 2 | Blanket `2>/dev/null` without diagnosis | 2 |
| 3 | Hardcoded fallback for missing required config | 4 |
| 4 | "Scoped to file X" when spec said repo-wide | 3 |
| 5 | `t.Skip("flaky")` without ticket | 5 |
| 6 | Comment-out assertion to silence test | 5 |
| 7 | `try/except: pass` silent error swallow | 2 |
| 8 | Mock the broken dependency forever | 2 |
| 9 | Rename variable to avoid linter warning | 1 |
| 10 | Disable CI step instead of fixing it | 5 |
| 11 | Manual override that should be automated | 4 |
| 12 | Catch-all error handler returning null | 2 |

## Reference

| File | Purpose |
|---|---|
| [`prompts/decision-tree.md`](prompts/decision-tree.md) | 4-question gate as a mermaid flowchart + plain-text fallback |
| [`prompts/anti-pattern-catalog.md`](prompts/anti-pattern-catalog.md) | 12 bad-vs-good entries with real session-debt references |
| [`prompts/workaround-template.md`](prompts/workaround-template.md) | Standard `// WORKAROUND:` comment template + 5-question smell test |
| [`README.md`](README.md) | Operator-facing overview, install path, expected adopter benefits |
| [`tests/test-skill-shape.sh`](tests/test-skill-shape.sh) | Bash shape tests (front-matter, prompt files, catalog count, mermaid presence, template fields) |

## Install

`git pull`. The skill is purely declarative — no hooks, no settings.json edits, no install script. Skill loaders that read `core/*/SKILL.md` discover this skill automatically.

For project-scoped activation, symlink or copy `core/fix-root-cause/` into `<repo>/.claude/skills/fix-root-cause/`.

## Uninstall

1. Delete `core/fix-root-cause/` (or unlink it from `<repo>/.claude/skills/fix-root-cause/`).
2. Remove the v1.6.0 row from `CHANGELOG.md` and the bullet in `README.md` "Status".

No global state to revert. The skill writes nothing at runtime.

## Citation backbone

Operator's anti-lying-fix rule [Source: user MEMORY.md `feedback_zero_issues_golden_rule.md`]; SDLC discipline [Source: user MEMORY.md `feedback_follow_sdlc_strictly.md`]; underscore-evasion incident 2026-05-04 [Source: orchestrator pin, ciscrm Wave 2 B1-B sub-agent — anonymized in catalog]; anti-fantasy sibling rule [Source: claude-skills `core/core-config/SKILL.md` §1]; pre-merge audit composition [Source: claude-skills `core/audit/SKILL.md`].
