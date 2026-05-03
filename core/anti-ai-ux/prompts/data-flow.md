# Show data flow — framework patterns

Principle 5 of `anti-ai-ux`: when the agent fetches, transforms, or routes data, surface a `source → action → destination` breadcrumb. Add a trust signal naming each source ("3 sources fetched: 1 cache hit, 1 live, 1 stale-by-2-min"). For LLM calls, show token usage and dollar cost.

## Why

"Based on your data" is the answer of an agent that does not want to be questioned. Naming the sources turns the answer into a citation — the user can follow the trail, verify, and trust.

The three sub-patterns each close a specific failure mode:

| Sub-pattern | Failure mode it closes |
|---|---|
| Source → action → destination breadcrumb | "I checked some sources" without naming them |
| Per-source freshness signal (cache / live / stale) | Stale data presented as authoritative |
| Token + dollar cost surface for LLM calls | Surprise bills; user has no real-time meter |
| Citation links from claims to source documents | Ungrounded claims indistinguishable from grounded |

## Source breadcrumb schema

```ts
interface SourceRef {
  id: string;                // stable identifier
  kind: 'doc' | 'api' | 'db' | 'file' | 'web' | 'memory';
  label: string;             // "audit-spec.md", "GET /v1/customers", "embeddings cache"
  url?: string;              // optional clickable link back to the source
  freshness: 'live' | 'cache' | 'stale';
  fetchedAt?: string;        // ISO timestamp
  staleSince?: string;       // ISO timestamp the data went stale
}

interface DataFlow {
  sources: SourceRef[];
  action: string;            // "summarize", "rerank", "generate fix candidates"
  destination: string;       // "chat reply", "audit-report.md", "Linear ticket"
  llm?: {
    model: string;
    inputTokens: number;
    outputTokens: number;
    estimatedUSD: number;    // pre-call estimate; replace with actuals post-call
  };
}
```

The `freshness` field renders as a colored chip:

- `live` (green) — fetched in the last call, no cache layer
- `cache` (blue) — served from a cache that was warm and within freshness window
- `stale` (amber) — served from cache but the freshness window expired; surface explicitly

A user who sees `2 live, 1 stale` reading a critical answer will (correctly) hesitate, click in, and either accept the staleness or refresh. A user who sees only "based on your data" cannot make that decision.

## React — `<DataFlowBreadcrumb>` component

```tsx
// components/DataFlowBreadcrumb.tsx
type Freshness = 'live' | 'cache' | 'stale';

interface SourceRef {
  id: string;
  kind: 'doc' | 'api' | 'db' | 'file' | 'web' | 'memory';
  label: string;
  url?: string;
  freshness: Freshness;
  fetchedAt?: string;
  staleSince?: string;
}

const freshTone: Record<Freshness, string> = {
  live: 'bg-emerald-100 text-emerald-800',
  cache: 'bg-sky-100 text-sky-800',
  stale: 'bg-amber-100 text-amber-800',
};

export function DataFlowBreadcrumb({
  sources, action, destination, llm,
}: {
  sources: SourceRef[];
  action: string;
  destination: string;
  llm?: { model: string; inputTokens: number; outputTokens: number; estimatedUSD: number };
}) {
  const summary = sources.reduce<Record<Freshness, number>>(
    (acc, s) => ({ ...acc, [s.freshness]: (acc[s.freshness] ?? 0) + 1 }),
    { live: 0, cache: 0, stale: 0 },
  );

  return (
    <aside className="rounded border border-slate-200 p-3 text-xs">
      <header className="flex items-center gap-2 font-medium">
        <span>{sources.length} sources</span>
        <span className="text-slate-500">·</span>
        <span>{summary.live} live, {summary.cache} cache, {summary.stale} stale</span>
        <span className="text-slate-500">·</span>
        <span>{action}</span>
        <span className="text-slate-500">→</span>
        <span>{destination}</span>
      </header>

      <ul className="mt-2 flex flex-wrap gap-1.5">
        {sources.map((s) => (
          <li key={s.id} className={`rounded px-1.5 py-0.5 ${freshTone[s.freshness]}`}>
            {s.url
              ? <a href={s.url} target="_blank" rel="noreferrer">{s.kind}: {s.label}</a>
              : <span>{s.kind}: {s.label}</span>}
            {s.freshness === 'stale' && s.staleSince && (
              <span className="ml-1 italic">stale since {new Date(s.staleSince).toLocaleString()}</span>
            )}
          </li>
        ))}
      </ul>

      {llm && (
        <p className="mt-2 text-slate-600">
          {llm.model} — {llm.inputTokens.toLocaleString()} in + {llm.outputTokens.toLocaleString()} out tokens
          {' · '}
          <span className="font-medium">${llm.estimatedUSD.toFixed(4)}</span>
        </p>
      )}
    </aside>
  );
}
```

## Vue 3 — `<DataFlowBreadcrumb>` component

```vue
<!-- components/DataFlowBreadcrumb.vue -->
<script setup lang="ts">
import { computed } from 'vue';

type Freshness = 'live' | 'cache' | 'stale';
interface SourceRef {
  id: string;
  kind: 'doc' | 'api' | 'db' | 'file' | 'web' | 'memory';
  label: string;
  url?: string;
  freshness: Freshness;
  fetchedAt?: string;
  staleSince?: string;
}

const props = defineProps<{
  sources: SourceRef[];
  action: string;
  destination: string;
  llm?: { model: string; inputTokens: number; outputTokens: number; estimatedUSD: number };
}>();

const summary = computed(() => {
  const acc: Record<Freshness, number> = { live: 0, cache: 0, stale: 0 };
  for (const s of props.sources) acc[s.freshness]++;
  return acc;
});

const freshTone: Record<Freshness, string> = {
  live: 'bg-emerald-100 text-emerald-800',
  cache: 'bg-sky-100 text-sky-800',
  stale: 'bg-amber-100 text-amber-800',
};
</script>

<template>
  <aside class="rounded border border-slate-200 p-3 text-xs">
    <header class="flex items-center gap-2 font-medium">
      <span>{{ sources.length }} sources</span>
      <span class="text-slate-500">·</span>
      <span>{{ summary.live }} live, {{ summary.cache }} cache, {{ summary.stale }} stale</span>
      <span class="text-slate-500">·</span>
      <span>{{ action }}</span>
      <span class="text-slate-500">→</span>
      <span>{{ destination }}</span>
    </header>

    <ul class="mt-2 flex flex-wrap gap-1.5">
      <li v-for="s in sources" :key="s.id"
          :class="['rounded px-1.5 py-0.5', freshTone[s.freshness]]">
        <a v-if="s.url" :href="s.url" target="_blank" rel="noreferrer">{{ s.kind }}: {{ s.label }}</a>
        <span v-else>{{ s.kind }}: {{ s.label }}</span>
        <span v-if="s.freshness === 'stale' && s.staleSince" class="ml-1 italic">
          stale since {{ new Date(s.staleSince).toLocaleString() }}
        </span>
      </li>
    </ul>

    <p v-if="llm" class="mt-2 text-slate-600">
      {{ llm.model }} — {{ llm.inputTokens.toLocaleString() }} in +
      {{ llm.outputTokens.toLocaleString() }} out tokens
      ·
      <span class="font-medium">${{ llm.estimatedUSD.toFixed(4) }}</span>
    </p>
  </aside>
</template>
```

## Svelte 5 — `<DataFlowBreadcrumb>` runes component

Per-source freshness chips classified via `$derived` from the row's `fetchedAt` + a freshness window. LLM cost surfaces twice: a pre-call `$state` estimate seeded from input tokens, then an `$effect` swap to the post-call actual when the response settles. Citation links render from a typed `Source[]` via `{#each}`. If the route lives under SvelteKit, the breadcrumb pulls its sources from `$page.data` populated by `+layout.server.ts`, so every nested route gets the same provenance context for free.

```svelte
<!-- src/lib/DataFlowBreadcrumb.svelte -->
<script lang="ts">
  type Freshness = 'live' | 'cache' | 'stale';
  type Kind = 'doc' | 'api' | 'db' | 'file' | 'web' | 'memory';
  interface SourceRef {
    id: string;
    kind: Kind;
    label: string;
    url?: string;
    fetchedAt?: string;          // ISO timestamp
    freshnessWindowMs?: number;  // optional override; default 60_000
  }
  interface LlmCost {
    model: string;
    inputTokens: number;
    outputTokens: number;
    estimatedUSD: number;
    actualUSD?: number;          // populated after the call resolves
  }

  let {
    sources,
    action,
    destination,
    llm,
    actualCostPromise,           // optional; resolves with the post-call cost
  }: {
    sources: SourceRef[];
    action: string;
    destination: string;
    llm?: LlmCost;
    actualCostPromise?: Promise<{ inputTokens: number; outputTokens: number; usd: number }>;
  } = $props();

  // freshness classification — per-source $derived, computed against now()
  function classify(s: SourceRef): Freshness {
    if (!s.fetchedAt) return 'cache';
    const age = Date.now() - new Date(s.fetchedAt).getTime();
    const window = s.freshnessWindowMs ?? 60_000;
    if (age < 1_000) return 'live';
    return age < window ? 'cache' : 'stale';
  }

  const enriched = $derived(sources.map((s) => ({ ...s, freshness: classify(s) })));
  const summary = $derived.by(() => {
    const acc: Record<Freshness, number> = { live: 0, cache: 0, stale: 0 };
    for (const s of enriched) acc[s.freshness]++;
    return acc;
  });

  const freshTone: Record<Freshness, string> = {
    live: 'bg-emerald-100 text-emerald-800',
    cache: 'bg-sky-100 text-sky-800',
    stale: 'bg-amber-100 text-amber-800',
  };

  // pre-call estimate vs post-call actual cost
  let displayCost = $state(llm?.estimatedUSD);
  let costLabel = $state<'estimate' | 'actual'>('estimate');

  $effect(() => {
    if (!actualCostPromise) return;
    let cancelled = false;
    actualCostPromise.then((c) => {
      if (cancelled) return;
      displayCost = c.usd;
      costLabel = 'actual';
    });
    return () => { cancelled = true; };
  });
</script>

<aside class="rounded border border-slate-200 p-3 text-xs">
  <header class="flex items-center gap-2 font-medium">
    <span>{enriched.length} sources</span>
    <span class="text-slate-500">·</span>
    <span>{summary.live} live, {summary.cache} cache, {summary.stale} stale</span>
    <span class="text-slate-500">·</span>
    <span>{action}</span>
    <span class="text-slate-500">→</span>
    <span>{destination}</span>
  </header>

  <ul class="mt-2 flex flex-wrap gap-1.5">
    {#each enriched as s (s.id)}
      <li class="rounded px-1.5 py-0.5 {freshTone[s.freshness]}">
        {#if s.url}
          <a href={s.url} target="_blank" rel="noreferrer">{s.kind}: {s.label}</a>
        {:else}
          <span>{s.kind}: {s.label}</span>
        {/if}
        {#if s.freshness === 'stale' && s.fetchedAt}
          <span class="ml-1 italic">stale since {new Date(s.fetchedAt).toLocaleString()}</span>
        {/if}
      </li>
    {/each}
  </ul>

  {#if llm}
    <p class="mt-2 text-slate-600">
      {llm.model} — {llm.inputTokens.toLocaleString()} in + {llm.outputTokens.toLocaleString()} out tokens
      ·
      <span class="font-medium">
        ${displayCost?.toFixed(4)} ({costLabel})
      </span>
    </p>
  {/if}
</aside>
```

For SvelteKit, hoist provenance into `+layout.server.ts` so any descendant route can render the breadcrumb without re-fetching:

```ts
// src/routes/+layout.server.ts
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals, fetch }) => {
  const sources = await locals.provenance.list();   // [{ id, kind, label, fetchedAt, ... }]
  return { sources };                                // available as $page.data.sources
};
```

```svelte
<!-- src/routes/+layout.svelte -->
<script lang="ts">
  import { page } from '$app/state';
  import DataFlowBreadcrumb from '$lib/DataFlowBreadcrumb.svelte';
</script>

<DataFlowBreadcrumb sources={page.data.sources}
                    action="rerank"
                    destination="chat reply"
                    llm={page.data.llmCost} />

<slot />
```

This way every nested page renders with consistent provenance context, and the freshness `$derived` recomputes on every navigation without extra wiring.

## Flutter — `DataFlowBreadcrumb` widget

```dart
// lib/widgets/data_flow_breadcrumb.dart
import 'package:flutter/material.dart';

enum Freshness { live, cache, stale }
enum SourceKind { doc, api, db, file, web, memory }

class SourceRef {
  final String id;
  final SourceKind kind;
  final String label;
  final String? url;
  final Freshness freshness;
  final DateTime? fetchedAt;
  final DateTime? staleSince;

  const SourceRef({
    required this.id,
    required this.kind,
    required this.label,
    this.url,
    required this.freshness,
    this.fetchedAt,
    this.staleSince,
  });
}

class LlmCost {
  final String model;
  final int inputTokens;
  final int outputTokens;
  final double estimatedUsd;
  const LlmCost({
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.estimatedUsd,
  });
}

class DataFlowBreadcrumb extends StatelessWidget {
  final List<SourceRef> sources;
  final String action;
  final String destination;
  final LlmCost? llm;

  const DataFlowBreadcrumb({
    super.key,
    required this.sources,
    required this.action,
    required this.destination,
    this.llm,
  });

  Color _toneOf(Freshness f) {
    switch (f) {
      case Freshness.live:  return Colors.green.shade100;
      case Freshness.cache: return Colors.lightBlue.shade100;
      case Freshness.stale: return Colors.amber.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = <Freshness, int>{Freshness.live: 0, Freshness.cache: 0, Freshness.stale: 0};
    for (final s in sources) summary[s.freshness] = (summary[s.freshness] ?? 0) + 1;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${sources.length} sources · '
            '${summary[Freshness.live]} live, ${summary[Freshness.cache]} cache, ${summary[Freshness.stale]} stale '
            '· $action → $destination',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: sources.map((s) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _toneOf(s.freshness),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${s.kind.name}: ${s.label}', style: const TextStyle(fontSize: 10)),
              );
            }).toList(),
          ),
          if (llm != null) ...[
            const SizedBox(height: 6),
            Text(
              '${llm!.model} — ${llm!.inputTokens} in + ${llm!.outputTokens} out tokens · '
              '\$${llm!.estimatedUsd.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}
```

## SwiftUI — `DataFlowBreadcrumb` view

```swift
// DataFlowBreadcrumb.swift
import SwiftUI

enum Freshness: String { case live, cache, stale
    var tone: Color {
        switch self {
        case .live:  return .green.opacity(0.18)
        case .cache: return .blue.opacity(0.18)
        case .stale: return .orange.opacity(0.22)
        }
    }
}

struct SourceRef: Identifiable {
    let id: String
    let kind: String
    let label: String
    let url: URL?
    let freshness: Freshness
    let staleSince: Date?
}

struct LlmCost {
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let estimatedUSD: Double
}

struct DataFlowBreadcrumb: View {
    let sources: [SourceRef]
    let action: String
    let destination: String
    let llm: LlmCost?

    private var summary: (Int, Int, Int) {
        var l = 0, c = 0, s = 0
        for src in sources {
            switch src.freshness {
            case .live:  l += 1
            case .cache: c += 1
            case .stale: s += 1
            }
        }
        return (l, c, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let (live, cache, stale) = summary
            Text("\(sources.count) sources · \(live) live, \(cache) cache, \(stale) stale · \(action) → \(destination)")
                .font(.caption.weight(.semibold))
            FlexibleStack(spacing: 4) {
                ForEach(sources) { s in
                    Text("\(s.kind): \(s.label)")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(s.freshness.tone)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            if let l = llm {
                Text("\(l.model) — \(l.inputTokens) in + \(l.outputTokens) out tokens · $\(String(format: "%.4f", l.estimatedUSD))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// FlexibleStack omitted — use any flow-layout helper, or fall back to LazyVGrid / VStack of HStacks
```

## Citation links — claim → source

When the model says "the audit gate refuses to merge while CRITICAL findings are open," the rendered claim must link back to its source. Footnote-style is preferred over hover tooltips (mobile / accessibility):

```tsx
<p>
  The audit gate refuses to merge while CRITICAL findings are open
  <sup className="text-xs"><a href="#src-charter-§6">[1]</a></sup>.
</p>

<aside id="src-charter-§6" className="mt-4 border-t pt-2 text-xs">
  [1] charter-v1.1.md §6 — line 184: <code>Zero-deferral on CRITICAL or HIGH</code>.
</aside>
```

The footnote anchors to a specific line in the source. The user clicks, scrolls, verifies. This is the trust contract for grounded answers.

## Cost transparency — pre-call estimate, post-call actual

Every LLM call renders a cost meter twice:

1. **Pre-call estimate.** Computed from `inputTokens` (known) + max_tokens budget + per-model rate. Renders as `~$0.0042 (estimate)`.
2. **Post-call actual.** Replaces the estimate when the response completes. Renders as `$0.0038`.

For long-running flows (multi-step agent loops), accumulate a session total at the top of the UI. Users who see "$1.27 spent this session" make different choices than users who don't.

## Anti-patterns to avoid

| Anti-pattern | Why it fails |
|---|---|
| `"Based on your data"` without naming sources | Indistinguishable from hallucination |
| Cache + live + stale rendered identically | User cannot tell freshness; treats stale as authoritative |
| Token / cost surface only post-call | Surprise bills; no opportunity to abort |
| Citation in tooltip-only | Mobile / accessibility hostile |
| Source list without a freshness chip per source | "Some are stale" is not actionable |
| Estimated cost rendered after actual cost | Estimate becomes irrelevant; remove if no longer used |
| Source labels obscured (`source_42`, `doc_id_xyz`) | Names exist for a reason — render them |
| Action verb missing from breadcrumb | User sees sources + destination but not what was DONE to them |
| Cost rendered without model name | $0.04 means very different things on Haiku vs Opus |

## Citations

- [Anthropic citations API](https://docs.claude.com/en/docs/build-with-claude/citations) — vendor-supported source attribution
- [Anthropic pricing](https://docs.claude.com/en/docs/about-claude/pricing) — per-model token rates
- [HTTP `Cache-Control` semantics](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) — freshness model
- [W3C "Provenance Vocabulary"](https://www.w3.org/TR/prov-overview/) — source/action/destination terminology
- [React `<a>` external link safety](https://web.dev/external-anchors-use-rel-noopener/) — `rel="noreferrer"` on every external citation link
- [Svelte 5 `$effect` reference](https://svelte.dev/docs/svelte/$effect) — pre-call estimate → post-call actual cost swap
- [SvelteKit `+layout.server.ts` load](https://svelte.dev/docs/kit/load) — hoist provenance into shared layout data
