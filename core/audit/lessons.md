# `core/audit` — lessons.md

Append-only log of corrections, revisit triggers, and rollback conditions
specific to the `audit` skill. Per charter §7 SLO: lessons observed →
regression test landed within 24 hours.

## 2026-04-28 — `feat:audit-disclaimer` revisit trigger

- **Shipped:** AI-provenance disclaimer pinned in `core/audit/SKILL.md`
  frontmatter as `ai_disclaimer:`, rendered as a Markdown blockquote-italic
  before the trailing `AUDIT-DONE` token. See
- **Hypothesis to be tested:** procurement DD reviewers will cite the
  AI-provenance marker in checklist closures (governance-density signal,
  #1" C5-F2 framing — NOT solo-engineer "I'm being honest" framing).
- **Revisit date:** **2026-07-27** (90 days post-merge, per spec AC7).
- **Rollback condition:** if **zero** procurement DD requests cite the
  AI-provenance marker in the 90-day window (operator-attested via inbox
  grep or written note in this file under a `### 2026-07-27 — revisit`
  heading), revert the disclaimer per `core/audit/SKILL.md` `## Uninstall`.
- **Keep condition:** ≥1 cited request → keep; consider promoting the
  pattern to other `core/` skills per spec NG3/NG4 deferral logic.
- **Banner-blindness watch:** the panel flagged that footers lose signal by
  week 4. The 90-day measurement window is a deliberate design off-ramp,
  not a hidden risk; if the keep-condition fires AND DD reviewers report
  the footer has become invisible, escalate to a v1.3 design revisit
  (header-banner alternative was rejected by C5-F3 and would need a
  charter §-anchor change to revisit).
