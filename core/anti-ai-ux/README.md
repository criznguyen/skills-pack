# `anti-ai-ux` — five UX patterns for agent-driven UIs

When the agent generates user-facing UI for a Claude-powered or agent-driven product, this skill teaches it to apply five anti-AI UX patterns by default: real-time progress, visible rollback, explain reasoning, consent before destructive ops, and show data flow. Patterns ship as per-framework code examples for React, Vue 3, Svelte, Flutter, and SwiftUI.

This README is the operator-facing onboarding. The agent-facing primer is [`SKILL.md`](SKILL.md); concrete code idioms are in `prompts/*.md`.

## Quick start — no install action required

The skill is pure declarative knowledge. There is no hook, no settings.json edit, no daemon. Adoption is two steps:

1. `git pull` (or copy `core/anti-ai-ux/` into your `~/.claude/skills/`).
2. Mention "AI chat UI", "agent dashboard", "Claude-powered app", or any of the trigger phrases in `SKILL.md` §"When to apply" while editing UI files in a React / Vue / Svelte / Flutter / SwiftUI project. The skill auto-attaches.

That's it. The patterns activate when the agent author UI; they do not interfere with non-UI work.

## Why adopters benefit

| Pain point | What the skill changes |
|---|---|
| **"My AI app feels untrustworthy"** — users dismiss responses without engaging | Five concrete patterns the agent applies by default; the UI surfaces *why* the model said what it said, not just *what* |
| **"Users hit irreversible operations and rage-quit"** | Pattern 2 (visible rollback) ships an undo stack pattern per framework; pattern 4 (consent) adds a preview stage before destructive writes |
| **"Streaming is hard to get right"** | Pattern 1 (real-time progress) ships per-framework streaming code (React `Suspense` + `ReadableStream`, Vue `<Suspense>` + `for await`, Flutter `StreamBuilder`, SwiftUI `AsyncStream`) |
| **"Decisions feel like a black box"** | Pattern 3 (explain reasoning) ships the decision-card schema: `{action, why, confidence, sources}` with confidence bands instead of raw floats |
| **"My LLM bills are surprising"** | Pattern 5 (show data flow) requires token + dollar cost rendering BEFORE the call, not after |

The five patterns are derived from the Fansipan Phase 9+ launch postmortem (user MEMORY.md `project_fansipan_phase9_complete.md` + `feedback_anti_ai_ux.md` 2026-04-16). The same five gaps recurred across every AI surface the operator shipped; the same five counter-patterns each closed the gap.

## What the skill does NOT do

| Concern | Where it lives instead |
|---|---|
| Streaming the API response itself | `claude-api` skill (Anthropic SDK setup); this skill handles the UI envelope |
| Model selection / cost optimization at the API layer | `claude-api` skill |
| Backend audit log of agent actions | `audit` + `governance-pack` skills |
| Pre-commit gate enforcing pattern adoption | NOT shipped in v1.5.0 — pattern adherence is review-time guidance, not hook-enforced. Future v1.6.x candidate if external adopter signal demands it |

## Compose with

- **`claude-api`** — the API-side streaming primitive feeds the UI-side progress pattern. Both must trigger together; this skill assumes `claude-api` has wired the streaming endpoint.
- **`core-config`** — anti-fantasy: never reference a framework hook / API the agent has not verified exists. UI code is just as susceptible to invented imports as backend code.
- **`simplify`** — apply after each pattern is introduced. The decision card should not have 12 fields; the undo stack should not persist 100 entries.
- **`audit`** (optional) — for v1.5.0+ teams that audit pre-merge, "are the 5 principles applied to AI surfaces in the diff?" is a worthwhile PE-dimension checklist add. Not mandatory in v1.5.0.

## Files in this skill

| Path | Purpose | Lines |
|---|---|---|
| [`SKILL.md`](SKILL.md) | Frontmatter + agent-facing skill body | ~180 |
| [`README.md`](README.md) | This file (operator-facing) | ~110 |
| [`prompts/streaming.md`](prompts/streaming.md) | Real-time progress patterns + 5 framework examples | ~210 |
| [`prompts/rollback.md`](prompts/rollback.md) | Visible-rollback patterns + persistence strategies | ~200 |
| [`prompts/reasoning.md`](prompts/reasoning.md) | Decision-card schema + confidence bands + alternatives | ~200 |
| [`prompts/consent-destructive.md`](prompts/consent-destructive.md) | Two-stage preview → confirm + idempotency keys | ~200 |
| [`prompts/data-flow.md`](prompts/data-flow.md) | Source breadcrumbs + cost transparency + citations | ~210 |
| [`tests/test-skill-shape.sh`](tests/test-skill-shape.sh) | Bash test — front-matter, prompt-file count, code-block sanity | ~120 |

## Tests

```bash
bash core/anti-ai-ux/tests/test-skill-shape.sh
```

Verifies:

1. `SKILL.md` exists with valid front-matter (`name:`, `description:` required keys present).
2. `README.md` exists and is non-empty.
3. All 5 prompt files exist under `prompts/`.
4. Each prompt file contains ≥3 fenced code blocks (per-framework code idioms).
5. Each prompt file contains an "Anti-pattern" or "Anti-patterns" section.
6. `SKILL.md` references all 5 prompt files (defensive against rename drift).
7. Front-matter `description:` field length is 200–500 chars (auto-attach quality).

Pass/fail summary: `PASS=N FAIL=0` → exit 0.

## Status

Shipped in claude-skills v1.5.0 (2026-05-04). Source: this commit.

Adoption signals to watch (90-day post-public-launch):

- 1+ external PR referencing the decision-card pattern as adopted in their Claude-powered product.
- 0 operator complaints about the trigger phrases over-firing on non-AI UI work.
- 1+ revisit if a framework newer than React/Vue/Svelte/Flutter/SwiftUI gains operator share (e.g. SolidJS, Lynx, Compose Multiplatform).

## Citation backbone

Operator's UX rule [Source: user MEMORY.md `feedback_anti_ai_ux.md` 2026-04-16]; Fansipan Phase 9 launch postmortem [Source: user MEMORY.md `project_fansipan_phase9_complete.md`]; vendor docs cited per framework in each `prompts/*.md` file.
