# Idea evaluation rubric

> Use BEFORE you commit to spec'ing or implementing a new dep / library /
> pattern / service / architectural change. Cite this file from your own
> thought or paste the verdict block into `docs/decisions/<date>-<slug>.md`.
>
> NOT a skill. NOT a sub-agent. The user (or the active session model) reads
> this file and decides. Auto-classification is forbidden by charter §3.

## 1. Four-lens score (R4)

For the proposed idea, score each lens 1 (low) – 5 (high) and add a 1-line verdict.

- **Necessity** — does the project need this NOW? Is there a measured pain
  signal (latency SLO breach, compliance deadline, recurring bug class)?
  Score 1 if "shiny on HN today"; score 5 if "compliance dated 2026-Q3".
- **Compatibility** — does this fit the current stack/conventions? How many
  files / call sites / contracts move? Score 1 if "schema-of-record swap".
- **Risk** — blast radius if we get it wrong. Auth / payment / migrations /
  data paths default to ≥3. Score 5 = irrecoverable.
- **Reversibility** — cost in person-days to roll back if it goes bad.
  Score 1 = "every PR has to handle both worlds for years" (R2 §2.6
  sunk-cost migration). Score 5 = "feature flag, removed in <1d".

## 2. Anti-pattern signal scan (R2 §3)

Scan the idea description for these phrases. Each match shifts the verdict
toward DEFER or REJECT and surfaces the named failure mode.

| Phrase / shape in the idea | Likely failure mode |
|---|---|
| "while we're already in there", "+1 day to existing ticket", "just one more thing" | Feature creep |
| "let's make it pluggable / generic / DRY this up" with ≤3 instances | Premature abstraction |
| "platform / framework that other teams can build on" — no first consumer named | Architectural astronautics |
| Justification leads with another company's name ("Netflix does X") | Cargo-culting |
| New framework / ORM / build tool touching >20% of codebase | Framework rot |
| Migration whose minimum unit is "the whole system", no deletion date for old | Sunk-cost migration |
| Title contains "AND" linking heterogeneous workstreams; one approval gate | Bundle poisoning |
| "We can make it configurable / let users choose" resolving a design fight | Optionality-by-flag |
| "Industry standard" / "best practice" / "future-proof" with no local-fit analysis | Cargo-culting + Framework rot |

## 3. Pre-mortem prompt (R1 §3.15, charter §4 5-line "what could go wrong")

Imagine 3 months from now this idea has shipped and *failed*. In ≤5 bullets,
write the most plausible autopsy. (Klein 2007 HBR — prospective hindsight
lifts failure-mode identification by ~30% over generic "what could go wrong".)

## 4. Score → verdict guidance (heuristic, not arithmetic)

The four-lens score is decision support, not a formula. Use these rough bands;
the WHAT-WOULD-CHANGE-MY-MIND line documents your override.

- **REJECT** — any of: Necessity ≤2 with no compliance/deadline forcing
  function; Reversibility = 1 (schema-of-record swap, language migration with
  no deletion date); ≥2 anti-pattern phrases match; pre-mortem surfaces a
  plausible irrecoverable failure mode.
- **DEFER** — Necessity 2–3 with no measurement yet; Risk ≥4 but
  Reversibility ≥3 (instrument first, decide later); single anti-pattern
  phrase match worth re-examining after a 1–2 week instrumentation window.
- **ADOPT** — Necessity ≥4 (compliance, named SLO breach, recurring bug
  class), no anti-pattern matches, pre-mortem reduces to integration risk
  manageable by feature flag or staged rollout.

A high Risk score is not by itself a REJECT — it raises the ceremony depth
in §5 (system-change vs feature) but does not gate entry.

## 5. Verdict block (paste into `decisions.md`)

```
IDEA: <one-sentence>
Necessity      N/5  <one-line why>
Compatibility  N/5  <one-line why>
Risk           N/5  <one-line why>
Reversibility  N/5  <one-line why>
ANTI-PATTERNS  <none | feature-creep | cargo-culting | ...>
PRE-MORTEM     <top 1 plausible failure>
VERDICT: ADOPT | DEFER | REJECT
TASK-CLASS if ADOPT: trivial | small | feature | system-change  (charter §3)
WHAT WOULD CHANGE MY MIND: <falsifiable condition>
```

## 6. After ADOPT

Hand off to the charter §3 task-class rubric (`core/core-config/CLAUDE.md`
§8). The four task classes pick ceremony depth; this rubric only gates
whether the idea enters at all.

## 7. Citations

- Charter v1.1 §3 (task-class rubric) — downstream gate after ADOPT.
- Charter v1.1 §4 phase 4 (mandatory 5-line "what could go wrong") — pre-mortem origin.
- Charter v1.1 §2.5 (verifiability) — why a deterministic rubric beats "Opus has it memorized".
- R1 §3.3 RICE / §3.14 ICE / §3.15 Pre-mortem (Klein 2007 HBR) / §3.12 NABC.
- R2 §2 (8 named anti-patterns) and §3 (phrase → failure-mode matrix).
- R4 §3 (4-lens hybrid C+B format) and §5 (anti-ceremony 4/4 PASS criteria).
- ADOPT-03 precedent: `core/audit/prompts/security-checklist.md` (shipped v1.1.1, 2026-04-28).
