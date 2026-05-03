# Consent before destructive — framework patterns

Principle 4 of `anti-ai-ux`: two-stage flow for any destructive op — PREVIEW (what will change, list of affected entities, diff) → CONFIRM (explicit click). For high-blast-radius ops (>50 entities, irreversible, cross-tenant), add a third stage requiring the user to type a confirmation string.

## Why

A confirm dialog without a preview teaches users to dismiss confirms. A preview teaches them what the agent is actually about to do — and surfaces the bug *before* it executes. The two-stage flow turns "click yes to make pain stop" into "see exactly what's about to happen, decide."

The third stage (typed confirmation) is for ops the user cannot undo: deleting a tenant, sending a million emails, dropping a database table. The friction is intentional; it costs the user 5 seconds and saves them a postmortem.

## Reversibility classification

Color, copy, and friction-level all derive from this enum. The agent must classify every destructive op into one of these buckets BEFORE rendering the consent UI.

| Class | Examples | UI cue | Friction |
|---|---|---|---|
| `reversible` | rename file, edit text field, change preference | blue accent | one click after preview |
| `local-irreversible` | delete file (recoverable from git/version-control), close issue | amber accent | one click after preview |
| `external-irreversible` | send email, charge card, post to social, delete-without-backup | red accent | typed confirmation |
| `blast-radius-large` | rename 50+ files, delete 100+ rows, cross-tenant write | red accent + warning banner | typed confirmation + count must match |

The `class` is metadata on the op, not a separate code path. The same `<ConsentDialog>` component handles all four; it parameterizes friction based on `class`.

## Idempotency keys

Every destructive op carries an idempotency key (UUID v4 generated client-side at the *preview* stage). The server stores keys with their result for 24 h. If the user double-clicks the confirm button, the second request returns the first request's result instead of executing twice.

```ts
const idempotencyKey = crypto.randomUUID();
fetch('/api/delete', {
  method: 'POST',
  headers: { 'Idempotency-Key': idempotencyKey, 'Content-Type': 'application/json' },
  body: JSON.stringify({ id }),
});
```

Server side (Express example):

```ts
const seen = new Map<string, unknown>(); // 24h LRU; production uses Redis

app.post('/api/delete', async (req, res) => {
  const key = req.header('Idempotency-Key');
  if (key && seen.has(key)) return res.json(seen.get(key));
  const result = await actuallyDelete(req.body.id);
  if (key) seen.set(key, result);
  res.json(result);
});
```

## React — two-stage `<ConsentDialog>` with preview

```tsx
// components/ConsentDialog.tsx
import { useState, useId } from 'react';

type DestructiveClass = 'reversible' | 'local-irreversible' | 'external-irreversible' | 'blast-radius-large';

export interface ConsentSpec {
  title: string;
  destructiveClass: DestructiveClass;
  affected: { kind: string; label: string }[];
  preview: React.ReactNode;
  confirmLabel?: string;
  typedConfirmation?: string;
}

const tone: Record<DestructiveClass, { ring: string; button: string }> = {
  'reversible':            { ring: 'ring-sky-300',    button: 'bg-sky-600' },
  'local-irreversible':    { ring: 'ring-amber-300',  button: 'bg-amber-600' },
  'external-irreversible': { ring: 'ring-rose-300',   button: 'bg-rose-600' },
  'blast-radius-large':    { ring: 'ring-rose-400',   button: 'bg-rose-700' },
};

export function ConsentDialog({
  spec,
  onCancel,
  onConfirm,
}: {
  spec: ConsentSpec;
  onCancel: () => void;
  onConfirm: (idempotencyKey: string) => Promise<void>;
}) {
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState(false);
  const idempotencyKey = useId(); // stable per dialog instance
  const t = tone[spec.destructiveClass];

  const requiresTyped = !!spec.typedConfirmation;
  const typedOk = !requiresTyped || typed === spec.typedConfirmation;

  async function handleConfirm() {
    if (busy || !typedOk) return;
    setBusy(true);
    try { await onConfirm(idempotencyKey); }
    finally { setBusy(false); }
  }

  return (
    <div role="dialog" aria-modal className={`rounded-md p-4 ring-2 ${t.ring}`}>
      <h2 className="text-lg font-semibold">{spec.title}</h2>

      <section className="mt-3">
        <p className="text-sm font-medium">Affected ({spec.affected.length}):</p>
        <ul className="mt-1 max-h-48 overflow-auto rounded border p-2 text-sm">
          {spec.affected.map((a, i) => <li key={i}>{a.kind}: {a.label}</li>)}
        </ul>
      </section>

      <section className="mt-3">
        <p className="text-sm font-medium">Preview:</p>
        <div className="mt-1 max-h-64 overflow-auto rounded border p-2 text-xs">{spec.preview}</div>
      </section>

      {requiresTyped && (
        <label className="mt-3 block text-sm">
          Type <code className="rounded bg-slate-100 px-1">{spec.typedConfirmation}</code> to confirm:
          <input
            type="text"
            value={typed}
            onChange={(e) => setTyped(e.target.value)}
            className="mt-1 w-full rounded border px-2 py-1 font-mono text-sm"
          />
        </label>
      )}

      <footer className="mt-4 flex justify-end gap-2">
        <button onClick={onCancel} className="rounded border px-3 py-1.5">Cancel</button>
        <button
          onClick={handleConfirm}
          disabled={!typedOk || busy}
          className={`rounded px-3 py-1.5 text-white disabled:opacity-50 ${t.button}`}
        >
          {busy ? 'Working…' : (spec.confirmLabel ?? 'Confirm')}
        </button>
      </footer>
    </div>
  );
}
```

Caller pattern (the agent invokes `ConsentDialog` BEFORE the destructive write):

```tsx
const idempotencyKey = useRef(crypto.randomUUID());

async function onConfirm(key: string) {
  await fetch('/api/agent/rename-batch', {
    method: 'POST',
    headers: { 'Idempotency-Key': key, 'Content-Type': 'application/json' },
    body: JSON.stringify({ plan }),
  });
}
```

## Vue 3 — `<ConsentDialog>` with preview

```vue
<!-- components/ConsentDialog.vue -->
<script setup lang="ts">
import { ref, computed } from 'vue';

type DestructiveClass = 'reversible' | 'local-irreversible' | 'external-irreversible' | 'blast-radius-large';
interface Affected { kind: string; label: string; }
interface Props {
  title: string;
  destructiveClass: DestructiveClass;
  affected: Affected[];
  confirmLabel?: string;
  typedConfirmation?: string;
}

const props = defineProps<Props>();
const emit = defineEmits<{ cancel: []; confirm: [key: string] }>();

const typed = ref('');
const busy = ref(false);
const idempotencyKey = crypto.randomUUID();

const requiresTyped = computed(() => !!props.typedConfirmation);
const typedOk = computed(() => !requiresTyped.value || typed.value === props.typedConfirmation);

const tone: Record<DestructiveClass, { ring: string; button: string }> = {
  'reversible':            { ring: 'ring-sky-300',    button: 'bg-sky-600' },
  'local-irreversible':    { ring: 'ring-amber-300',  button: 'bg-amber-600' },
  'external-irreversible': { ring: 'ring-rose-300',   button: 'bg-rose-600' },
  'blast-radius-large':    { ring: 'ring-rose-400',   button: 'bg-rose-700' },
};

async function handleConfirm() {
  if (busy.value || !typedOk.value) return;
  busy.value = true;
  try { emit('confirm', idempotencyKey); } finally { busy.value = false; }
}
</script>

<template>
  <div role="dialog" aria-modal :class="['rounded-md p-4 ring-2', tone[destructiveClass].ring]">
    <h2 class="text-lg font-semibold">{{ title }}</h2>

    <section class="mt-3">
      <p class="text-sm font-medium">Affected ({{ affected.length }}):</p>
      <ul class="mt-1 max-h-48 overflow-auto rounded border p-2 text-sm">
        <li v-for="(a, i) in affected" :key="i">{{ a.kind }}: {{ a.label }}</li>
      </ul>
    </section>

    <section class="mt-3">
      <p class="text-sm font-medium">Preview:</p>
      <div class="mt-1 max-h-64 overflow-auto rounded border p-2 text-xs">
        <slot name="preview" />
      </div>
    </section>

    <label v-if="requiresTyped" class="mt-3 block text-sm">
      Type <code class="rounded bg-slate-100 px-1">{{ typedConfirmation }}</code> to confirm:
      <input v-model="typed" type="text"
             class="mt-1 w-full rounded border px-2 py-1 font-mono text-sm" />
    </label>

    <footer class="mt-4 flex justify-end gap-2">
      <button class="rounded border px-3 py-1.5" @click="emit('cancel')">Cancel</button>
      <button :disabled="!typedOk || busy" @click="handleConfirm"
              :class="['rounded px-3 py-1.5 text-white disabled:opacity-50', tone[destructiveClass].button]">
        {{ busy ? 'Working…' : (confirmLabel ?? 'Confirm') }}
      </button>
    </footer>
  </div>
</template>
```

## Svelte 5 — two-stage `<ConsentDialog>` with preview

Two stages tracked client-side via `$state` (`'preview' | 'confirm'`); reversibility class drives a `$derived` accent + friction setting; idempotency key generated when stage 1 mounts and reused at confirm; high-blast-radius ops require typed confirmation. Diff/preview snapshot is stored in `$state.frozen` so transient stage-1 transitions cannot mutate the immutable plan after the user reviewed it.

```svelte
<!-- src/lib/ConsentDialog.svelte -->
<script lang="ts">
  type DestructiveClass =
    | 'reversible'
    | 'local-irreversible'
    | 'external-irreversible'
    | 'blast-radius-large';

  interface Affected { kind: string; label: string; }
  interface ConsentSpec {
    title: string;
    destructiveClass: DestructiveClass;
    affected: Affected[];
    diffSnapshot: unknown;          // immutable preview payload (rendered as a slot or as JSON)
    confirmLabel?: string;
    typedConfirmation?: string;     // required when class is external-irreversible / blast-radius-large
  }

  let {
    spec,
    oncancel,
    onconfirm,
  }: {
    spec: ConsentSpec;
    oncancel: () => void;
    onconfirm: (idempotencyKey: string) => Promise<void>;
  } = $props();

  // Stage tracker — preview FIRST, then confirm. No skipping.
  let stage = $state<'preview' | 'confirm'>('preview');
  let typed = $state('');
  let busy = $state(false);

  // Idempotency key generated ONCE when the preview opens; reused when the user advances to confirm.
  // Server stores key→result for 24h so a double-submit returns the first result.
  const idempotencyKey = crypto.randomUUID();

  // Frozen snapshot — stage-1 cannot mutate after the user has read it.
  const frozenDiff = $state.frozen(spec.diffSnapshot);

  // Reversibility classification → tone + friction (derived signal so callers can switch class freely).
  const tone = $derived.by(() => {
    switch (spec.destructiveClass) {
      case 'reversible':            return { ring: 'ring-sky-300',   button: 'bg-sky-600',    badge: 'bg-sky-100 text-sky-800' };
      case 'local-irreversible':    return { ring: 'ring-amber-300', button: 'bg-amber-600',  badge: 'bg-amber-100 text-amber-800' };
      case 'external-irreversible': return { ring: 'ring-rose-300',  button: 'bg-rose-600',   badge: 'bg-rose-100 text-rose-800' };
      case 'blast-radius-large':    return { ring: 'ring-rose-400',  button: 'bg-rose-700',   badge: 'bg-rose-200 text-rose-900' };
    }
  });
  const requiresTyped = $derived(
    spec.destructiveClass === 'external-irreversible' ||
    spec.destructiveClass === 'blast-radius-large' ||
    !!spec.typedConfirmation,
  );
  const typedOk = $derived(!requiresTyped || typed === (spec.typedConfirmation ?? ''));

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault();
    if (stage === 'preview') { stage = 'confirm'; return; }
    if (busy || !typedOk) return;
    busy = true;
    try { await onconfirm(idempotencyKey); }
    finally { busy = false; }
  }
</script>

<form role="dialog" aria-modal="true"
      class="rounded-md p-4 ring-2 {tone.ring}"
      onsubmit={handleSubmit}>
  <header class="flex items-baseline justify-between">
    <h2 class="text-lg font-semibold">{spec.title}</h2>
    <span class="rounded px-1.5 py-0.5 text-xs uppercase tracking-wide {tone.badge}">
      {spec.destructiveClass}
    </span>
  </header>

  <section class="mt-3">
    <p class="text-sm font-medium">Affected ({spec.affected.length}):</p>
    <ul class="mt-1 max-h-48 overflow-auto rounded border p-2 text-sm">
      {#each spec.affected as a}<li>{a.kind}: {a.label}</li>{/each}
    </ul>
  </section>

  {#if stage === 'preview'}
    <section class="mt-3">
      <p class="text-sm font-medium">Preview (immutable snapshot):</p>
      <pre class="mt-1 max-h-64 overflow-auto rounded border p-2 text-xs">{JSON.stringify(frozenDiff, null, 2)}</pre>
    </section>
  {:else}
    <section class="mt-3 text-sm text-slate-700">
      Reviewed preview above. Idempotency key: <code class="rounded bg-slate-100 px-1 text-xs">{idempotencyKey}</code>
    </section>

    {#if requiresTyped}
      <label class="mt-3 block text-sm">
        Type <code class="rounded bg-slate-100 px-1">{spec.typedConfirmation}</code> to confirm:
        <input type="text" bind:value={typed}
               class="mt-1 w-full rounded border px-2 py-1 font-mono text-sm" />
      </label>
    {/if}
  {/if}

  <footer class="mt-4 flex justify-end gap-2">
    <button type="button" onclick={oncancel} class="rounded border px-3 py-1.5">Cancel</button>
    <button type="submit"
            disabled={stage === 'confirm' && (!typedOk || busy)}
            class="rounded px-3 py-1.5 text-white disabled:opacity-50 {tone.button}">
      {#if stage === 'preview'}Review →{:else}{busy ? 'Working…' : (spec.confirmLabel ?? 'Confirm')}{/if}
    </button>
  </footer>
</form>
```

If you prefer **SvelteKit form actions** (server-validated, progressively-enhanced, no JS required for the confirm POST), keep the same component for the preview UI and let stage 2 submit through `+page.server.ts`:

```ts
// src/routes/agent/destructive/+page.server.ts
import { fail } from '@sveltejs/kit';
import type { Actions } from './$types';

const seen = new Map<string, unknown>(); // 24h LRU; production uses Redis

export const actions: Actions = {
  confirm: async ({ request }) => {
    const data = await request.formData();
    const key = data.get('idempotencyKey')?.toString();
    if (!key) return fail(400, { error: 'missing idempotency key' });
    if (seen.has(key)) return { ok: true, replayed: true, result: seen.get(key) };

    const typed = data.get('typed')?.toString() ?? '';
    const required = data.get('typedConfirmation')?.toString() ?? '';
    if (required && typed !== required) return fail(400, { error: 'typed confirmation mismatch' });

    const result = await runDestructiveOp(/* … */);
    seen.set(key, result);
    return { ok: true, replayed: false, result };
  },
};
```

The component above renders `<form method="POST" action="?/confirm">` in the SvelteKit case and passes `idempotencyKey`, `typed`, and `typedConfirmation` as hidden form fields — same idempotency contract as the React/Vue examples, but with progressive enhancement built in.

## Flutter — `ConsentDialog` widget

```dart
// lib/widgets/consent_dialog.dart
import 'dart:math';
import 'package:flutter/material.dart';

enum DestructiveClass { reversible, localIrreversible, externalIrreversible, blastRadiusLarge }

class ConsentSpec {
  final String title;
  final DestructiveClass destructiveClass;
  final List<({String kind, String label})> affected;
  final Widget preview;
  final String? confirmLabel;
  final String? typedConfirmation;

  const ConsentSpec({
    required this.title,
    required this.destructiveClass,
    required this.affected,
    required this.preview,
    this.confirmLabel,
    this.typedConfirmation,
  });
}

class ConsentDialog extends StatefulWidget {
  final ConsentSpec spec;
  final Future<void> Function(String idempotencyKey) onConfirm;
  final VoidCallback onCancel;
  const ConsentDialog({
    super.key,
    required this.spec,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<ConsentDialog> {
  late final String _idempotencyKey;
  final _typed = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final r = Random.secure();
    _idempotencyKey = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Color _tone() {
    switch (widget.spec.destructiveClass) {
      case DestructiveClass.reversible: return Colors.lightBlue;
      case DestructiveClass.localIrreversible: return Colors.amber;
      case DestructiveClass.externalIrreversible: return Colors.red;
      case DestructiveClass.blastRadiusLarge: return Colors.red.shade700;
    }
  }

  bool get _typedOk =>
      widget.spec.typedConfirmation == null ||
      _typed.text == widget.spec.typedConfirmation;

  Future<void> _confirm() async {
    if (_busy || !_typedOk) return;
    setState(() => _busy = true);
    try { await widget.onConfirm(_idempotencyKey); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return AlertDialog(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: _tone(), width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      title: Text(spec.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Affected (${spec.affected.length}):', style: const TextStyle(fontWeight: FontWeight.w600)),
            ...spec.affected.map((a) => Text('  ${a.kind}: ${a.label}')),
            const SizedBox(height: 8),
            const Text('Preview:', style: TextStyle(fontWeight: FontWeight.w600)),
            spec.preview,
            if (spec.typedConfirmation != null) ...[
              const SizedBox(height: 12),
              Text('Type "${spec.typedConfirmation}" to confirm:'),
              TextField(controller: _typed, onChanged: (_) => setState(() {})),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
        FilledButton(
          onPressed: (_typedOk && !_busy) ? _confirm : null,
          style: FilledButton.styleFrom(backgroundColor: _tone()),
          child: Text(_busy ? 'Working…' : (spec.confirmLabel ?? 'Confirm')),
        ),
      ],
    );
  }
}
```

## SwiftUI — `ConsentSheet` view

```swift
// ConsentSheet.swift
import SwiftUI

enum DestructiveClass {
    case reversible, localIrreversible, externalIrreversible, blastRadiusLarge
    var tone: Color {
        switch self {
        case .reversible:           return .blue
        case .localIrreversible:    return .orange
        case .externalIrreversible: return .red
        case .blastRadiusLarge:     return .red
        }
    }
}

struct AffectedItem: Identifiable {
    let id = UUID()
    let kind: String
    let label: String
}

struct ConsentSheet<Preview: View>: View {
    let title: String
    let destructiveClass: DestructiveClass
    let affected: [AffectedItem]
    let typedConfirmation: String?
    let confirmLabel: String
    @ViewBuilder let preview: () -> Preview
    let onConfirm: (String) async -> Void
    let onCancel: () -> Void

    @State private var typed = ""
    @State private var busy = false
    private let idempotencyKey = UUID().uuidString

    private var typedOk: Bool {
        guard let required = typedConfirmation else { return true }
        return typed == required
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text("Affected (\(affected.count)):").font(.subheadline.weight(.semibold))
            ScrollView { VStack(alignment: .leading) {
                ForEach(affected) { Text("\($0.kind): \($0.label)").font(.callout) }
            }}.frame(maxHeight: 120)
            Text("Preview:").font(.subheadline.weight(.semibold))
            preview().font(.callout)
            if let req = typedConfirmation {
                Text("Type \"\(req)\" to confirm:")
                TextField("", text: $typed).textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced))
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Button(busy ? "Working…" : confirmLabel) {
                    busy = true
                    Task { await onConfirm(idempotencyKey); busy = false }
                }
                .disabled(!typedOk || busy)
                .buttonStyle(.borderedProminent)
                .tint(destructiveClass.tone)
            }
        }
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 12)
                 .stroke(destructiveClass.tone, lineWidth: 2))
    }
}
```

## Anti-patterns to avoid

| Anti-pattern | Why it fails |
|---|---|
| `confirm("Are you sure?")` yes-only dialog | No preview; teaches users to dismiss confirms |
| Single-stage destructive op (no preview) | User can't see what's about to happen |
| Same color/copy for `reversible` and `external-irreversible` | User can't distinguish low-stakes from high-stakes |
| No idempotency key | Double-click executes twice; financial/email duplication |
| Typed confirmation matches case-insensitively | Lowers friction below the design intent |
| `confirmLabel = "OK"` for a destructive op | "OK" is ambiguous; use the verb ("Delete", "Send", "Charge") |
| Preview hidden behind a "details" toggle | Defeats the purpose; preview must be the default surface |
| Confirm button enabled while busy | Double-trigger possible; idempotency saves you but UX is jarring |
| Server ignores `Idempotency-Key` header | Client-side dedupe alone is insufficient (network retries) |

## Citations

- [Stripe idempotent requests](https://stripe.com/docs/api/idempotent_requests) — canonical pattern + 24h replay window
- [W3C ARIA dialog pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/)
- [React `useId`](https://react.dev/reference/react/useId)
- [Vue 3 `defineEmits`](https://vuejs.org/api/sfc-script-setup.html#defineprops-defineemits)
- [Svelte 5 `$state.frozen` reference](https://svelte.dev/docs/svelte/$state#$state.frozen) — immutable preview snapshot for stage-1
- [SvelteKit form actions](https://svelte.dev/docs/kit/form-actions) — server-side idempotency with progressive enhancement
- [Flutter `AlertDialog`](https://api.flutter.dev/flutter/material/AlertDialog-class.html)
- [SwiftUI `.confirmationDialog`](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:)-7t1xn) — for simple cases; the multi-stage flow above is for high-blast-radius ops
