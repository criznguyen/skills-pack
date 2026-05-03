# Explain reasoning — framework patterns

Principle 3 of `anti-ai-ux`: show *why* alongside *what* on every agent decision. Default surface is a "decision card" with `{action, why, confidence, sources, alternatives}`. Power users get a collapsible chain-of-thought panel.

## Why

Users cannot trust a black box, and they cannot correct it either. Naming reasons turns the decision into a debuggable artifact. The user can compare reasons against their mental model, agree, disagree, or escalate.

The five fields of the decision card each close a specific failure mode:

| Field | Failure mode it closes |
|---|---|
| `action` | "What did the agent decide?" — the core answer |
| `why: [reason1, reason2, …]` | "Trust me bro" — replaced with itemized rationale |
| `confidence: certain \| likely \| speculative` | False precision (raw `0.873124`) |
| `sources: [ref1, ref2, …]` | Ungrounded answers — every claim has a citation |
| `alternatives: [{option, why_rejected}, …]` | Hidden deliberation — the user sees what was considered |

A decision card without any one of these fields is incomplete. A card with all five renders trust visibly.

## Decision-card schema

```json
{
  "action": "Rename `internal/auth/jwt.go` → `internal/auth/token.go`",
  "why": [
    "The new module exports `Token` not `JWT`; the file should match the public type.",
    "All 3 imports already use `auth.Token`; the `JWT` alias is dead code.",
    "Repo convention (CONTRIBUTING.md §4): file name follows primary export."
  ],
  "confidence": "likely",
  "sources": [
    { "kind": "file", "path": "CONTRIBUTING.md", "line": 42 },
    { "kind": "grep", "pattern": "auth.Token", "matches": 3 }
  ],
  "alternatives": [
    {
      "option": "Keep `jwt.go`, add a deprecation comment",
      "why_rejected": "The file is exported, downstream importers should rename their reference; deprecation comment doesn't drive the rename."
    }
  ]
}
```

`confidence` is a band, not a float. Three values cover the field:

- `certain` — the action is mechanically determined (typo fix, lint auto-fix, file rename to match symbol).
- `likely` — the agent has strong evidence but reasonable people could disagree on tie-breaks.
- `speculative` — the agent is reasoning under partial information; user review is recommended.

## React — `<DecisionCard>` component

```tsx
// components/DecisionCard.tsx
import { useState } from 'react';

type Confidence = 'certain' | 'likely' | 'speculative';

export interface Decision {
  action: string;
  why: string[];
  confidence: Confidence;
  sources?: { kind: string; path?: string; line?: number; pattern?: string; matches?: number }[];
  alternatives?: { option: string; why_rejected: string }[];
  thinking?: string; // optional collapsible chain-of-thought
}

const tone: Record<Confidence, string> = {
  certain: 'border-emerald-400 bg-emerald-50',
  likely: 'border-sky-400 bg-sky-50',
  speculative: 'border-amber-400 bg-amber-50',
};

export function DecisionCard({ decision }: { decision: Decision }) {
  const [showThinking, setShowThinking] = useState(false);

  return (
    <article className={`rounded-md border p-3 ${tone[decision.confidence]}`}>
      <header className="flex items-baseline justify-between">
        <h3 className="font-semibold">{decision.action}</h3>
        <span className="text-xs uppercase tracking-wide">{decision.confidence}</span>
      </header>

      <section className="mt-2">
        <p className="text-sm font-medium">Why:</p>
        <ul className="mt-1 list-disc pl-5 text-sm">
          {decision.why.map((r, i) => <li key={i}>{r}</li>)}
        </ul>
      </section>

      {decision.alternatives && decision.alternatives.length > 0 && (
        <section className="mt-3 text-sm">
          <p className="font-medium">Considered &amp; rejected:</p>
          <ul className="mt-1 list-disc pl-5">
            {decision.alternatives.map((a, i) => (
              <li key={i}>
                <span className="font-mono text-xs">{a.option}</span>
                {' — '}{a.why_rejected}
              </li>
            ))}
          </ul>
        </section>
      )}

      {decision.sources && decision.sources.length > 0 && (
        <footer className="mt-3 flex flex-wrap gap-2 text-xs text-slate-600">
          {decision.sources.map((s, i) => (
            <span key={i} className="rounded border border-slate-300 px-1.5 py-0.5">
              {s.kind === 'file' ? `${s.path}:${s.line}` : `${s.pattern} (${s.matches})`}
            </span>
          ))}
        </footer>
      )}

      {decision.thinking && (
        <details
          className="mt-3 text-xs"
          open={showThinking}
          onToggle={(e) => setShowThinking((e.target as HTMLDetailsElement).open)}
        >
          <summary className="cursor-pointer">Chain-of-thought (advanced)</summary>
          <pre className="mt-1 whitespace-pre-wrap rounded bg-white/50 p-2">{decision.thinking}</pre>
        </details>
      )}
    </article>
  );
}
```

## Vue 3 — `<DecisionCard>` component

```vue
<!-- components/DecisionCard.vue -->
<script setup lang="ts">
import { ref } from 'vue';

type Confidence = 'certain' | 'likely' | 'speculative';
interface Source { kind: string; path?: string; line?: number; pattern?: string; matches?: number; }
interface Alternative { option: string; why_rejected: string; }
interface Decision {
  action: string;
  why: string[];
  confidence: Confidence;
  sources?: Source[];
  alternatives?: Alternative[];
  thinking?: string;
}

const props = defineProps<{ decision: Decision }>();
const showThinking = ref(false);

const tone: Record<Confidence, string> = {
  certain: 'border-emerald-400 bg-emerald-50',
  likely: 'border-sky-400 bg-sky-50',
  speculative: 'border-amber-400 bg-amber-50',
};
</script>

<template>
  <article :class="['rounded-md border p-3', tone[decision.confidence]]">
    <header class="flex items-baseline justify-between">
      <h3 class="font-semibold">{{ decision.action }}</h3>
      <span class="text-xs uppercase tracking-wide">{{ decision.confidence }}</span>
    </header>

    <section class="mt-2">
      <p class="text-sm font-medium">Why:</p>
      <ul class="mt-1 list-disc pl-5 text-sm">
        <li v-for="(r, i) in decision.why" :key="i">{{ r }}</li>
      </ul>
    </section>

    <section v-if="decision.alternatives?.length" class="mt-3 text-sm">
      <p class="font-medium">Considered &amp; rejected:</p>
      <ul class="mt-1 list-disc pl-5">
        <li v-for="(a, i) in decision.alternatives" :key="i">
          <span class="font-mono text-xs">{{ a.option }}</span>
          — {{ a.why_rejected }}
        </li>
      </ul>
    </section>

    <details v-if="decision.thinking" class="mt-3 text-xs" :open="showThinking">
      <summary class="cursor-pointer" @click="showThinking = !showThinking">
        Chain-of-thought (advanced)
      </summary>
      <pre class="mt-1 whitespace-pre-wrap rounded bg-white/50 p-2">{{ decision.thinking }}</pre>
    </details>
  </article>
</template>
```

## Svelte 5 — `<DecisionCard>` runes component

```svelte
<!-- src/lib/DecisionCard.svelte -->
<script lang="ts">
  type Confidence = 'certain' | 'likely' | 'speculative';
  interface Source { kind: string; path?: string; line?: number; pattern?: string; matches?: number; }
  interface Alternative { option: string; why_rejected: string; }
  interface Decision {
    action: string;
    why: string[];
    confidence: Confidence;
    sources?: Source[];
    alternatives?: Alternative[];
    thinking?: string;
  }

  let { decision }: { decision: Decision } = $props();
  let showThinking = $state(false);

  // confidence band classification derived from the decision input
  const tone: Record<Confidence, string> = {
    certain: 'border-emerald-400 bg-emerald-50',
    likely: 'border-sky-400 bg-sky-50',
    speculative: 'border-amber-400 bg-amber-50',
  };
  const bandClass = $derived(tone[decision.confidence]);
  const bandLabel = $derived(decision.confidence.toUpperCase());
</script>

<article class="rounded-md border p-3 {bandClass}">
  <header class="flex items-baseline justify-between">
    <h3 class="font-semibold">{decision.action}</h3>
    <span class="text-xs uppercase tracking-wide">{bandLabel}</span>
  </header>

  <section class="mt-2">
    <p class="text-sm font-medium">Why:</p>
    <ul class="mt-1 list-disc pl-5 text-sm">
      {#each decision.why as r}<li>{r}</li>{/each}
    </ul>
  </section>

  {#if decision.alternatives && decision.alternatives.length > 0}
    <section class="mt-3 text-sm">
      <p class="font-medium">Considered &amp; rejected:</p>
      <ul class="mt-1 list-disc pl-5">
        {#each decision.alternatives as a}
          <li><span class="font-mono text-xs">{a.option}</span> — {a.why_rejected}</li>
        {/each}
      </ul>
    </section>
  {/if}

  {#if decision.sources && decision.sources.length > 0}
    <footer class="mt-3 flex flex-wrap gap-2 text-xs text-slate-600">
      {#each decision.sources as s}
        <span class="rounded border border-slate-300 px-1.5 py-0.5">
          {s.kind === 'file' ? `${s.path}:${s.line}` : `${s.pattern} (${s.matches})`}
        </span>
      {/each}
    </footer>
  {/if}

  {#if decision.thinking}
    <details class="mt-3 text-xs" open={showThinking}
             ontoggle={(e) => (showThinking = (e.currentTarget as HTMLDetailsElement).open)}>
      <summary class="cursor-pointer">Chain-of-thought (advanced)</summary>
      <pre class="mt-1 whitespace-pre-wrap rounded bg-white/50 p-2"
           transition:slide>{decision.thinking}</pre>
    </details>
  {/if}
</article>

<script lang="ts">
  // import the slide transition at the top of the file in real code:
  // import { slide } from 'svelte/transition';
</script>
```

The `$derived` runes turn `bandClass` and `bandLabel` into reactive signals that re-evaluate only when `decision.confidence` changes — confidence-band classification is centralised, not duplicated at every render site. The `transition:slide` on the chain-of-thought `<pre>` gives a smooth expand/collapse without manual animation timing. Call site stays terse:

```svelte
<DecisionCard decision={{
  action: 'Rename internal/auth/jwt.go → internal/auth/token.go',
  why: ['Module exports Token not JWT', 'All 3 imports use auth.Token'],
  confidence: 'likely',
  sources: [{ kind: 'file', path: 'CONTRIBUTING.md', line: 42 }],
  alternatives: [{ option: 'Keep jwt.go', why_rejected: 'deprecation comment doesn\'t drive the rename' }],
}} />
```

## Flutter — `DecisionCard` widget

```dart
// lib/widgets/decision_card.dart
import 'package:flutter/material.dart';

enum Confidence { certain, likely, speculative }

class DecisionSource {
  final String kind;
  final String? path;
  final int? line;
  const DecisionSource({required this.kind, this.path, this.line});
}

class Alternative {
  final String option;
  final String whyRejected;
  const Alternative({required this.option, required this.whyRejected});
}

class Decision {
  final String action;
  final List<String> why;
  final Confidence confidence;
  final List<DecisionSource> sources;
  final List<Alternative> alternatives;
  final String? thinking;

  const Decision({
    required this.action,
    required this.why,
    required this.confidence,
    this.sources = const [],
    this.alternatives = const [],
    this.thinking,
  });
}

class DecisionCard extends StatefulWidget {
  final Decision decision;
  const DecisionCard({super.key, required this.decision});

  @override
  State<DecisionCard> createState() => _DecisionCardState();
}

class _DecisionCardState extends State<DecisionCard> {
  bool _showThinking = false;

  Color _tone(Confidence c) {
    switch (c) {
      case Confidence.certain: return Colors.green.shade50;
      case Confidence.likely: return Colors.lightBlue.shade50;
      case Confidence.speculative: return Colors.amber.shade50;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.decision;
    return Card(
      color: _tone(d.confidence),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(d.action, style: Theme.of(context).textTheme.titleMedium)),
                Text(d.confidence.name.toUpperCase(),
                    style: const TextStyle(fontSize: 11, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Why:', style: TextStyle(fontWeight: FontWeight.w600)),
            ...d.why.map((r) => Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2),
                  child: Text('• $r'),
                )),
            if (d.alternatives.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Considered & rejected:', style: TextStyle(fontWeight: FontWeight.w600)),
              ...d.alternatives.map((a) => Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: Text('• ${a.option} — ${a.whyRejected}'),
                  )),
            ],
            if (d.thinking != null)
              ExpansionTile(
                title: const Text('Chain-of-thought (advanced)'),
                onExpansionChanged: (v) => setState(() => _showThinking = v),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(d.thinking!, style: const TextStyle(fontFamily: 'monospace')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
```

## SwiftUI — `DecisionCard` view

```swift
// DecisionCard.swift
import SwiftUI

enum Confidence: String { case certain, likely, speculative }

struct DecisionSource: Identifiable {
    let id = UUID()
    let kind: String
    let path: String?
    let line: Int?
}

struct Alternative: Identifiable {
    let id = UUID()
    let option: String
    let whyRejected: String
}

struct Decision {
    let action: String
    let why: [String]
    let confidence: Confidence
    let sources: [DecisionSource]
    let alternatives: [Alternative]
    let thinking: String?
}

struct DecisionCard: View {
    let decision: Decision
    @State private var showThinking = false

    private var toneColor: Color {
        switch decision.confidence {
        case .certain:     return .green.opacity(0.12)
        case .likely:      return .blue.opacity(0.12)
        case .speculative: return .orange.opacity(0.12)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(decision.action).font(.headline)
                Spacer()
                Text(decision.confidence.rawValue.uppercased())
                    .font(.caption2).tracking(1).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Why:").fontWeight(.semibold)
                ForEach(Array(decision.why.enumerated()), id: \.offset) { _, r in
                    Text("• \(r)").font(.callout)
                }
            }
            if !decision.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Considered & rejected:").fontWeight(.semibold)
                    ForEach(decision.alternatives) { a in
                        Text("• \(a.option) — \(a.whyRejected)").font(.callout)
                    }
                }
            }
            if let thinking = decision.thinking {
                DisclosureGroup("Chain-of-thought (advanced)", isExpanded: $showThinking) {
                    Text(thinking).font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(toneColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

## Confidence-band visualization

Use a 3-segment bar, not a percentage:

```
[ ████  ░░░░  ░░░░ ]  certain
[ ████  ████  ░░░░ ]  likely
[ ████  ████  ████ ]  speculative (more bars filled = MORE uncertainty surfaced)
```

Counter-intuitive but correct: `speculative` fills more bars because it surfaces *more* uncertainty to the user. `certain` is a single confident bar; the user reads "I'm done deliberating."

## Anti-patterns to avoid

| Anti-pattern | Why it fails |
|---|---|
| `"I picked B"` with no `why` | Pure black box; user cannot trust or correct |
| Confidence rendered as raw float `0.87` | False precision — users misread the third digit |
| Decision card lists only the chosen option | Hidden deliberation; user cannot tell what was rejected |
| Chain-of-thought always visible by default | Clutters the surface; advanced feature, default-collapsed |
| `why` field a single string blob | Itemized list = scannable; blob = wall of text |
| Sources without paths/line numbers | "Based on your data" without naming the data |
| Decision card without action verb | User scanning has to read 3 sentences to know *what* the agent did |

## Citations

- [Anthropic extended-thinking docs](https://docs.claude.com/en/docs/build-with-claude/extended-thinking) — chain-of-thought rendering
- [React `<details>` pattern](https://react.dev/reference/react-dom/components/details)
- [Vue 3 `<details>` and conditional rendering](https://vuejs.org/api/built-in-directives.html)
- [Svelte 5 `$derived` runes reference](https://svelte.dev/docs/svelte/$derived) — confidence-band classification as reactive signal
- [Flutter `ExpansionTile`](https://api.flutter.dev/flutter/material/ExpansionTile-class.html)
- [SwiftUI `DisclosureGroup`](https://developer.apple.com/documentation/swiftui/disclosuregroup)
