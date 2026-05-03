# Workaround comment template + smell test

When the 4-question gate in [`decision-tree.md`](decision-tree.md) returns ACCEPT (all four answers YES), the workaround ships with a standard comment shape so future agents and reviewers can find, evaluate, and remove it. This file specifies the template.

## Standard template

```text
// WORKAROUND: <one-line reason>
//   Why root cause not fixed: <time pressure / external dependency / scope cap>
//   Follow-up: <ISSUE-id or TODO-file path>
//   Reversibility: <how to undo + when to revisit>
//   Author: criznguyen, <YYYY-MM-DD>
```

The template adapts to language comment syntax:

```python
# WORKAROUND: <one-line reason>
#   Why root cause not fixed: <reason>
#   Follow-up: <ISSUE-id>
#   Reversibility: <plan>
#   Author: criznguyen, <YYYY-MM-DD>
```

```yaml
# WORKAROUND: <one-line reason>
#   Why root cause not fixed: <reason>
#   Follow-up: <ISSUE-id>
#   Reversibility: <plan>
#   Author: criznguyen, <YYYY-MM-DD>
```

```html
<!-- WORKAROUND: <one-line reason>
       Why root cause not fixed: <reason>
       Follow-up: <ISSUE-id>
       Reversibility: <plan>
       Author: criznguyen, <YYYY-MM-DD>
-->
```

## The 5 required fields

Every workaround comment MUST contain exactly these five fields, in this order, on consecutive lines. Missing any field is a `delta-code-review` BLOCK.

| # | Field | Format | Validation |
|---|---|---|---|
| 1 | `WORKAROUND:` | Free-text one-line reason | Must start with the literal `WORKAROUND:` (uppercase) |
| 2 | `Why root cause not fixed:` | Time pressure / external dep / scope cap / awaiting upstream / etc. | Must name a concrete reason, not "later" |
| 3 | `Follow-up:` | `ISSUE-<n>`, `TODO/<file>.md`, `PR#<n>`, etc. | Must resolve to a real, locatable artifact |
| 4 | `Reversibility:` | "When X, do Y" — names the trigger AND the action | Must NOT be "TBD" or empty |
| 5 | `Author:` | `criznguyen, <YYYY-MM-DD>` | Author MUST be `criznguyen` per `feedback_commit_author.md` |

## Worked example

```typescript
// WORKAROUND: skip TLS verify for vendor/payments staging — cert chain incomplete.
//   Why root cause not fixed: vendor support ticket VND-4421 open since 2026-04-12;
//                              ETA from vendor for fixed cert chain is 2026-05-15.
//   Follow-up: ISSUE-501 (re-enable TLS verify when VND-4421 closes)
//   Reversibility: when vendor confirms cert is fixed, delete this block AND the
//                   `tls.NoVerify=true` assignment 5 lines below; integration test
//                   `test_payments_staging_tls.py` must pass before merge.
//   Author: criznguyen, 2026-05-04
const client = new PaymentsClient({ tls: { rejectUnauthorized: false } });
```

This passes all five field-presence checks and articulates a removal trigger and action.

## Smell test (5 questions)

Before accepting any `// WORKAROUND:` block — operator-run mental checklist OR auditor-run pre-merge:

### 1. Could a 1-hour root-cause fix have replaced this 30-minute workaround?

If yes, the workaround should be rejected. The 4-question gate in `decision-tree.md` Q1 (time pressure) is meant to capture genuine emergencies, not "I'd rather not refactor this now." A 30-min workaround that displaces a 1-hour fix produces ~6-12 hours of compounded debt over a quarter.

### 2. Will the next agent recognize this as a workaround vs intended design?

The `WORKAROUND:` keyword + 5 required fields make this answerable: yes, the next agent will recognize it. Comments lacking the keyword (e.g. just "FIXME: hack") fail this test — they look like ordinary tech-debt notes and get rolled into the codebase as accidental architecture.

### 3. Is the follow-up actionable (someone owns it, has a deadline)?

`ISSUE-501` is a string until it resolves to a real ticket with assignee + due-date. The auditor verifies the resolution; the reviewer verifies the format. A "TODO" without owner is not actionable.

### 4. Will the reversibility plan still work in 6 months when the codebase has drifted?

Plans like "delete this block and the assignment 5 lines below" tend to break when the surrounding code refactors. Better plans name SYMBOLS or TESTS rather than line numbers:

- BAD: "delete this block and the line 5 below"
- GOOD: "delete this block; remove the `tls.NoVerify=true` assignment in `PaymentsClient` constructor; ensure `test_payments_staging_tls` passes"

The auditor flags brittle reversibility plans (line-number refs) as MEDIUM findings.

### 5. Are we adding to a pile of known workarounds that signals systemic debt?

Greppable count: `git grep -c "WORKAROUND:" -- '*.py' '*.go' '*.ts' '*.tsx' '*.sh' '*.yml'`. If the count exceeds ~10 in a project, the operator should consider a "workaround-clearing sprint" before adding more. A growing pile suggests the team is choosing the workaround path too readily; the gate may need stricter Q1 enforcement.

## Anti-pattern: comment without all 5 fields

```python
# WORKAROUND: cert is broken, will fix later
client = make_client(verify=False)
```

This fails fields 2, 3, 4, 5. The reviewer must reject; the agent must either complete the comment OR fix the root cause. "will fix later" is the universal red flag — there is no owner, no deadline, no plan.

## Anti-pattern: vague reversibility

```python
# WORKAROUND: temporary fix
#   Why root cause not fixed: out of time
#   Follow-up: ISSUE-?
#   Reversibility: TBD
#   Author: criznguyen, 2026-05-04
```

Has all 5 fields by count but Follow-up is `?` (unresolvable) and Reversibility is `TBD` (no content). Reviewer rejects — fields must be substantive, not placeholder.

## Anti-pattern: line-number reversibility

```python
# WORKAROUND: ...
#   Reversibility: delete lines 42-51 of this file
```

Brittle. Six months from now, lines 42-51 are something else entirely. Reviewer asks for symbol/test-named reversibility instead.

## Composition

- The reviewer (`core/delta-code-review/`) greps the diff for `WORKAROUND:` and validates the 5 fields are present + substantive.
- The auditor (`core/audit/`) walks `git grep "WORKAROUND:"` repo-wide as part of pre-merge PE review and flags brittle reversibility plans + missing follow-ups.
- The agent (during fix authoring) consults this template AFTER the gate in `decision-tree.md` returns ACCEPT, before staging the diff.
