# Real-time progress — framework patterns

Principle 1 of `anti-ai-ux`: stream tokens as they arrive; when streaming isn't possible, replace the spinner with a status string that names *what* is happening and *how much* is done.

## Why

A spinner is indistinguishable from a hung process. A streaming response gives the user the rhythm signal "this is making progress." A status string ("Analyzing 47 audit findings, 12 done") gives the same signal when streaming is structurally impossible (e.g. the model returns one JSON object after thinking). Either is acceptable; an opaque spinner is not.

The cheap-but-wrong escape hatch is `setTimeout`-faked streaming of a pre-computed response. Users sense the rhythm difference (real streams are jittery; fake streams are uniformly paced) and trust drops *more* than with no streaming. Use real streams or honest status strings.

## React + Anthropic SDK — `ReadableStream` + `Suspense`

```tsx
// app/chat/MessageStream.tsx
'use client';
import { useState, useEffect, useRef } from 'react';
import Anthropic from '@anthropic-ai/sdk';

export function MessageStream({ prompt }: { prompt: string }) {
  const [text, setText] = useState('');
  const [done, setDone] = useState(false);
  const cancelRef = useRef<AbortController>();

  useEffect(() => {
    cancelRef.current = new AbortController();
    const client = new Anthropic();
    (async () => {
      const stream = await client.messages.stream(
        {
          model: 'claude-opus-4-7',
          max_tokens: 1024,
          messages: [{ role: 'user', content: prompt }],
        },
        { signal: cancelRef.current!.signal },
      );
      for await (const event of stream) {
        if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
          setText(prev => prev + event.delta.text);
        }
      }
      setDone(true);
    })();
    return () => cancelRef.current?.abort();
  }, [prompt]);

  return (
    <div className="message">
      <pre>{text}</pre>
      {!done && <span aria-live="polite">Streaming…</span>}
    </div>
  );
}
```

Pair with `<Suspense fallback={<NamedStatus label="Connecting…" />}>` at the parent so the user sees a status string before the first token, not after.

## Vue 3 + Anthropic SDK — `<Suspense>` + `for await`

```vue
<!-- components/MessageStream.vue -->
<script setup lang="ts">
import { ref, watchEffect, onUnmounted } from 'vue';
import Anthropic from '@anthropic-ai/sdk';

const props = defineProps<{ prompt: string }>();
const text = ref('');
const done = ref(false);
let abort: AbortController | null = null;

watchEffect(async (onCleanup) => {
  abort?.abort();
  abort = new AbortController();
  text.value = '';
  done.value = false;
  onCleanup(() => abort?.abort());

  const client = new Anthropic();
  const stream = await client.messages.stream(
    {
      model: 'claude-opus-4-7',
      max_tokens: 1024,
      messages: [{ role: 'user', content: props.prompt }],
    },
    { signal: abort.signal },
  );
  for await (const event of stream) {
    if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
      text.value += event.delta.text;
    }
  }
  done.value = true;
});

onUnmounted(() => abort?.abort());
</script>

<template>
  <div class="message">
    <pre>{{ text }}</pre>
    <span v-if="!done" aria-live="polite">Streaming…</span>
  </div>
</template>
```

Wrap the component in `<Suspense>` at the call site so the SSR fallback renders a named status, not a blank pane.

## Svelte 5 — runes + `$effect` + async iterator

```svelte
<!-- src/lib/MessageStream.svelte -->
<script lang="ts">
  import Anthropic from '@anthropic-ai/sdk';

  let { prompt }: { prompt: string } = $props();
  let text = $state('');
  let done = $state(false);

  $effect(() => {
    const abort = new AbortController();
    text = '';
    done = false;
    (async () => {
      const client = new Anthropic();
      const stream = await client.messages.stream(
        {
          model: 'claude-opus-4-7',
          max_tokens: 1024,
          messages: [{ role: 'user', content: prompt }],
        },
        { signal: abort.signal },
      );
      for await (const event of stream) {
        if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
          text += event.delta.text;
        }
      }
      done = true;
    })();
    return () => abort.abort();
  });
</script>

<div class="message">
  <pre>{text}</pre>
  {#if !done}<span aria-live="polite">Streaming…</span>{/if}
</div>
```

## Flutter — `StreamBuilder<String>` over the SDK stream

```dart
// lib/widgets/message_stream.dart
import 'package:flutter/material.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';

class MessageStream extends StatelessWidget {
  final String prompt;
  const MessageStream({super.key, required this.prompt});

  Stream<String> _tokens() async* {
    final client = AnthropicClient(apiKey: const String.fromEnvironment('ANTHROPIC_API_KEY'));
    final req = CreateMessageRequest(
      model: Model.modelId('claude-opus-4-7'),
      maxTokens: 1024,
      messages: [Message(role: MessageRole.user, content: MessageContent.text(prompt))],
    );
    String acc = '';
    await for (final ev in client.createMessageStream(request: req)) {
      ev.map(
        contentBlockDelta: (d) {
          d.delta.map(
            textDelta: (t) {
              acc += t.text;
            },
            inputJsonDelta: (_) {},
          );
        },
        messageStart: (_) {},
        messageDelta: (_) {},
        messageStop: (_) {},
        contentBlockStart: (_) {},
        contentBlockStop: (_) {},
        ping: (_) {},
      );
      yield acc;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _tokens(),
      builder: (ctx, snap) {
        if (snap.hasError) return Text('Error: ${snap.error}');
        final text = snap.data ?? '';
        final streaming = snap.connectionState == ConnectionState.active;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(text),
            if (streaming) const Text('Streaming…', semanticsLabel: 'Streaming'),
          ],
        );
      },
    );
  }
}
```

The `Semantics` label is what assistive tech announces; pair it with a visible status string so sighted users see the same signal.

## SwiftUI — `AsyncStream` + `.task`

```swift
// MessageStream.swift
import SwiftUI

struct MessageStream: View {
    let prompt: String
    @State private var text = ""
    @State private var streaming = false

    var body: some View {
        VStack(alignment: .leading) {
            Text(text).textSelection(.enabled)
            if streaming {
                Text("Streaming…").foregroundStyle(.secondary)
            }
        }
        .task(id: prompt) {
            text = ""
            streaming = true
            defer { streaming = false }
            for await token in tokens(for: prompt) {
                text += token
            }
        }
    }

    private func tokens(for prompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                // Replace with your API client; the contract is: yield each
                // text-delta string as it arrives, then finish() at end.
                let client = AnthropicClient()
                do {
                    for try await event in client.streamMessage(prompt: prompt) {
                        if case .textDelta(let t) = event { continuation.yield(t) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

`.task(id: prompt)` automatically cancels the prior stream when `prompt` changes — the cancel-and-restart contract that React/Vue/Svelte/Flutter all need explicit `AbortController` plumbing for.

## Status-string fallback — when streaming is impossible

If the model returns one JSON object (tool-use, structured-output mode), there is nothing to stream. Replace the spinner with a status string that updates as the work progresses:

```tsx
const [status, setStatus] = useState('Connecting…');
// then, as work happens server-side via SSE / WebSocket:
//   setStatus('Analyzing 47 audit findings, 12 done');
//   setStatus('Generating fix candidates, 3 of 12');
```

The string MUST contain the count + denominator when known. "Analyzing…" alone is one rung up from a spinner; "Analyzing 12/47" is fully informative.

## Anti-patterns to avoid

| Anti-pattern | Why it fails |
|---|---|
| `<Spinner />` while the model thinks | Indistinguishable from hung process |
| `setTimeout(setText(prev + nextChar), 30)` over a pre-computed response | Users sense uniform pacing; trust drops |
| Render the full response only at end (atomic flip) | Loses the rhythm signal entirely |
| Status string `"Thinking…"` with no count | Same opacity problem as a spinner |
| No abort path on prompt-change | Prior stream keeps writing into stale state; visual flicker |
| Streaming UI that hides errors mid-stream | Stream errors become silent failures |

## Citations

- [Anthropic streaming API docs](https://docs.claude.com/en/api/messages-streaming)
- [React Suspense reference](https://react.dev/reference/react/Suspense)
- [Vue 3 `<Suspense>` reference](https://vuejs.org/guide/built-ins/suspense.html)
- [Svelte 5 `$effect` reference](https://svelte.dev/docs/svelte/$effect)
- [Flutter `StreamBuilder`](https://api.flutter.dev/flutter/widgets/StreamBuilder-class.html)
- [SwiftUI `AsyncStream`](https://developer.apple.com/documentation/swift/asyncstream)
