---
name: anti-ai-ux
description: Apply anti-AI UX patterns when generating user-facing UI for agent-driven products. Five principles — real-time progress, visible rollback, explain reasoning, consent before destructive ops, show data flow — codified for React, Vue 3, Svelte, Flutter, and SwiftUI projects. TRIGGER when generating UI components, screens, or flows in a project that imports `react`/`react-dom`/`vue`/`svelte`/`flutter`/`SwiftUI` AND the user mentions AI / chatbot / agent / Claude / assistant / autopilot / copilot / agentic UX. SKIP for backend code, internal CLI tooling, headless agents, or static marketing pages.
paths: ["**/*.tsx", "**/*.jsx", "**/*.vue", "**/*.svelte", "**/*.dart", "**/*.swift"]
when_to_use: Authoring or reviewing user-facing UI for an AI/agent-driven product where transparency, rollback, and consent patterns matter.
argument-hint: <ui-component-or-flow>
type: ux-conventions
tools: Read, Grep, Glob
model: opus
disable-model-invocation: false
postcondition_required: false
blast_radius: read-only
last-validated: 2026-05-03
---

# anti-ai-ux

Black-box AI products lose user trust the first time the user catches them silently doing something wrong. Transparent UX wins adoption — and "transparent" means five concrete patterns the agent must apply when authoring UI for an AI-driven product. This skill names the patterns, says when each one applies, and links to per-framework prompts (`prompts/*.md`) that show the exact code idioms.

## Why this skill exists

AI products fail user trust through five recurring failure modes:

1. **Opaque "Thinking..."** — the user has no idea whether the model is making progress or hung. Token-by-token streaming closes this gap.
2. **Irreversible destructive ops** — the agent renames 47 files, the user disagrees, and there is no undo. Every destructive op needs a visible rollback path.
3. **Black-box scoring / decisions** — the assistant says "I picked option B" with no reason. The user can neither trust nor correct the choice.
4. **Silent execution of writes** — the agent fills out a form and submits it with no confirm step. The user discovers what happened only after the fact.
5. **Hidden data sources** — the assistant cites "based on your data" without naming which data. The user cannot tell whether the answer is grounded or hallucinated.

Each failure mode has a counter-pattern. This skill packages the five counter-patterns as ready-to-paste guidance the agent can consult while authoring UI.

The patterns originate in the operator's `feedback_anti_ai_ux.md` memory entry and the Fansipan Phase 9+ launch postmortems: the same five gaps recurred across every AI product surface the operator shipped, and the same five counter-patterns each closed the gap.

## When to apply

The skill auto-attaches when the user prompt is about UI generation and the project context includes a UI-framework signal AND an AI signal:

| Project signal | Frameworks |
|---|---|
| `package.json` deps include `react` / `react-dom` / `next` | React + Next.js |
| `package.json` deps include `vue` / `nuxt` | Vue 3 / Nuxt |
| `package.json` deps include `svelte` / `@sveltejs/kit` | Svelte / SvelteKit |
| `pubspec.yaml` `dependencies:` block includes `flutter:` | Flutter |
| Any `*.swift` file containing `import SwiftUI` | SwiftUI |

| User prompt signal | Examples |
|---|---|
| "chatbot UI", "chat panel", "AI chat" | direct |
| "agent dashboard", "agent UI", "agentic UX" | direct |
| "Claude-powered app", "Anthropic SDK app" | direct (compose with `claude-api` skill) |
| "AI assistant", "copilot", "autopilot" | direct |
| "streaming response", "token streaming" | partial — apply principle 1 only |
| "undo", "rollback", "version history" for AI-driven actions | partial — apply principle 2 only |
| "explain why", "show reasoning", "decision card" | partial — apply principle 3 only |

Compose with `claude-api` when the project also imports the Anthropic SDK: `claude-api` handles model selection / prompt caching; this skill handles the UI envelope around the response.

## When NOT to apply

| Surface | Reason to skip |
|---|---|
| Backend API code (Express, FastAPI, Go HTTP servers) | No user-facing surface; this skill is UI-only |
| Internal CLI tooling and scripts | Operators read terminal output; the principles are UI-shaped |
| Headless agents / cron jobs / batch pipelines | No human in the loop |
| Static marketing pages | No agent-driven actions to confirm or roll back |
| Pure data-visualization dashboards (no AI in the loop) | The patterns target *AI* opacity; non-AI dashboards have different failure modes |
| Existing UI under refactor where the AI surface is unchanged | If the diff doesn't touch the AI envelope, don't widen scope |

If the project mixes both (e.g. a Next.js app with a Node API in the same monorepo), apply the skill ONLY to UI files (anything under `app/`, `components/`, `pages/`, `views/`, `lib/screens/`, `Views/`).

## The 5 principles

### 1. Real-time progress

**What.** Stream tokens to the screen as they arrive from the model. When a step takes >2 seconds and isn't streamable, replace the spinner with a status string that names *what* is happening and *how much* is done ("Analyzing 47 audit findings, 12 done").

**Why.** A spinner is indistinguishable from a hung process. The user must be able to tell, at a glance, whether progress is being made.

**Implementation hint.** Use the framework's native streaming primitive (`ReadableStream` + `Suspense` in React, `<Suspense>` + `for await` in Vue, `StreamBuilder` in Flutter, `AsyncStream` in SwiftUI). Never `setTimeout(...)`-fake-stream a pre-computed response — users sense the rhythm difference and trust drops further.

See [`prompts/streaming.md`](prompts/streaming.md) for per-framework code.

### 2. Visible rollback

**What.** Every destructive op (delete, overwrite, send, submit, irreversible state change) ships with an undo button. Show what was changed (diff view, list of affected entities). Maintain a 5–10 step undo stack persisted across sessions for high-stakes flows.

**Why.** AI agents make mistakes the user notices only after the fact. A reversible action is forgivable; an irreversible one is product-killing.

**Implementation hint.** Optimistic UI updates with rollback on error in React (`useReducer` with `[present, ...past]` history); `pinia` + `vue-undo-stack` in Vue; `Provider` + immutable `UndoState<T>` in Flutter; `@Observable` + history array in SwiftUI. Persist the history with `localStorage` / `SecureStore` (with size cap so the stack does not grow unboundedly).

See [`prompts/rollback.md`](prompts/rollback.md) for per-framework code.

### 3. Explain reasoning

**What.** Show *why* alongside *what* on every agent decision. The default surface is a "decision card": `{action, why: [reason1, reason2, ...], confidence, sources}`. A collapsible "chain-of-thought" panel lets advanced users dig deeper without cluttering the default view.

**Why.** Users cannot trust a black box, and they cannot correct it either. Naming reasons turns the decision into a debuggable artifact.

**Implementation hint.** Confidence renders as a band (`certain` / `likely` / `speculative`), not a raw percentage — users misread `0.87` as far more precise than it is. Always list at least one alternative the agent considered and rejected, with the reason for rejection. This anchors trust through *visible deliberation*.

See [`prompts/reasoning.md`](prompts/reasoning.md) for per-framework code.

### 4. Consent before destructive

**What.** Two-stage flow for any destructive op: PREVIEW (what will change, list of affected entities, diff) → CONFIRM (explicit click). For high-blast-radius ops (>50 entities, irreversible, cross-tenant), add a third stage requiring the user to type a confirmation string.

**Why.** A confirm dialog without a preview teaches users to dismiss confirms. A preview teaches them what the agent is actually about to do — and surfaces the bug *before* it executes.

**Implementation hint.** Distinguish reversible vs irreversible operations through copy and color. Use idempotency keys to prevent double-execution if the user accidentally double-clicks. Never rely on a "Are you sure?" yes-only dialog — show data, not abstract questions.

See [`prompts/consent-destructive.md`](prompts/consent-destructive.md) for per-framework code.

### 5. Show data flow

**What.** When the agent fetches, transforms, or routes data: surface a `source → action → destination` diagram or breadcrumb. Add a trust signal naming each source ("3 sources fetched: 1 cache hit, 1 live, 1 stale-by-2-min"). For LLM calls, show token usage and dollar cost.

**Why.** "I checked some sources" is the answer of an agent that does not want to be questioned. Naming sources turns answers into citations.

**Implementation hint.** Citations link back to their source documents. Cache vs live vs stale freshness is shown explicitly per source. For grounded answers, every claim renders with its source pinned next to it (footnote-style, not hidden in a tooltip). Cost transparency is non-negotiable in any UI that bills the user — token counts + dollar cost render before the call, not after.

See [`prompts/data-flow.md`](prompts/data-flow.md) for per-framework code.

## Compose with

| Skill | How they compose |
|---|---|
| `core-config` | Anti-fantasy applies to UI code too — never invent framework APIs; verify imports before referencing them. The principles encoded here are about *what UI to build*; `core-config` is about *how to build it correctly*. |
| `claude-api` | When the project also imports the Anthropic SDK, `claude-api` handles model selection, streaming, and prompt caching at the API layer; this skill handles the UI envelope (status string, decision card, undo, consent, citations). |
| `simplify` | Don't over-engineer the anti-AI UX itself. A decision card with 3 reasons + 1 confidence band beats a 12-field card with histogram. Apply `simplify` to the UX surface after each principle is introduced. |
| `audit` | Pre-merge audit must include "are the 5 principles applied to AI surfaces in the diff?" as a PE-dimension checklist item. Optional follow-on (not mandatory in v1.5.0). |

## Anti-patterns to avoid

These are the surface-level lies that the principles displace. Spotting any of them in your diff is a signal to apply the corresponding principle.

| Anti-pattern | Principle violated | Correct pattern |
|---|---|---|
| Opaque `<Spinner />` while the model thinks | 1 (progress) | Token-stream OR named-status string |
| `confirm("Delete?")` then irreversible delete | 2 + 4 (rollback + consent) | Two-stage preview-then-confirm + undo button |
| `setTimeout` "fake stream" of a pre-computed response | 1 (progress) | Real `ReadableStream` from the API |
| Decision UI: "I picked B" (no reason) | 3 (reasoning) | Decision card with `why` list + confidence band |
| "Are you sure?" yes-only dialog without preview | 4 (consent) | Preview the changes before asking |
| `"Based on your data"` without naming the data | 5 (data flow) | Source breadcrumb naming each source |
| Hidden cost: model bills $0.84 with no UI surface | 5 (data flow) | Token count + dollar cost before the call |
| `localStorage` undo stack growing unboundedly | 2 (rollback) | Cap at 10 entries; LRU evict |
| Confidence rendered as `0.873124` raw float | 3 (reasoning) | Band: `certain` / `likely` / `speculative` |
| Decision card listing only the chosen option | 3 (reasoning) | List ≥1 considered-and-rejected alternative |

## Reference

| File | Purpose |
|---|---|
| [`prompts/streaming.md`](prompts/streaming.md) | Real-time progress patterns for React, Vue 3, Svelte, Flutter, SwiftUI |
| [`prompts/rollback.md`](prompts/rollback.md) | Visible-rollback patterns + persistence strategies |
| [`prompts/reasoning.md`](prompts/reasoning.md) | Decision-card pattern + confidence bands + alternatives |
| [`prompts/consent-destructive.md`](prompts/consent-destructive.md) | Two-stage preview→confirm + idempotency keys |
| [`prompts/data-flow.md`](prompts/data-flow.md) | Source breadcrumbs + cost transparency + citation links |
| [`README.md`](README.md) | Operator-facing overview, install path, expected adopter benefits |

Each `prompts/*.md` includes ≥3 framework code examples and a closing "Anti-pattern" section.

## Install

`git pull`. The skill is purely declarative — no hooks, no settings.json edits, no install script. Skill loaders that read `core/*/SKILL.md` discover this skill automatically.

For project-scoped activation, symlink or copy `core/anti-ai-ux/` into `<repo>/.claude/skills/anti-ai-ux/`.

## Uninstall

1. Delete `core/anti-ai-ux/` (or unlink it from `<repo>/.claude/skills/anti-ai-ux/`).
2. Remove the v1.5.0 row from `CHANGELOG.md` and the bullet in `README.md` "Status".

No global state to revert. The skill writes nothing at runtime.

## Citation backbone

Operator's UX rule [Source: user MEMORY.md `feedback_anti_ai_ux.md` 2026-04-16 "UI must use anti-AI patterns — real-time progress, visible rollback, no black box"]; Fansipan Phase 9 anti-AI UX postmortem [Source: user MEMORY.md `project_fansipan_phase9_complete.md`]; Anthropic streaming SDK pattern [Source: https://docs.claude.com/en/api/messages-streaming]; React 18 Suspense + ReadableStream [Source: https://react.dev/reference/react/Suspense]; Flutter `StreamBuilder` [Source: https://api.flutter.dev/flutter/widgets/StreamBuilder-class.html]; SwiftUI `AsyncStream` [Source: https://developer.apple.com/documentation/swift/asyncstream]; idempotency keys for two-stage confirms [Source: https://stripe.com/docs/api/idempotent_requests]; Karpathy "no black box" UX framing [Source: docs/research/harness-skills-required/].
