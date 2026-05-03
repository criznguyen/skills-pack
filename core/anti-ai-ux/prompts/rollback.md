# Visible rollback — framework patterns

Principle 2 of `anti-ai-ux`: every destructive op ships with an undo button. Show what was changed (diff view, list of affected entities). Maintain a 5–10 step undo stack persisted across sessions for high-stakes flows.

## Why

AI agents make mistakes the user notices only after the fact (renamed wrong file, sent wrong email draft, deleted wrong row). A reversible action is forgivable; an irreversible one is product-killing. The undo button is the trust contract: "you can let me try, because you can take it back."

The contract has three parts: (a) optimistic UI shows the change immediately, (b) the prior state is preserved on a stack, (c) one click restores it. Persistence across sessions (localStorage / SecureStore) covers the case where the user closes the app before realizing the mistake.

## React — `useReducer` + history stack + optimistic UI

```tsx
// hooks/useUndo.ts
import { useReducer, useCallback } from 'react';

type State<T> = { past: T[]; present: T; future: T[] };
type Action<T> = { type: 'set'; next: T } | { type: 'undo' } | { type: 'redo' };

function reducer<T>(state: State<T>, action: Action<T>): State<T> {
  if (action.type === 'set') {
    const past = [...state.past, state.present].slice(-10); // cap at 10
    return { past, present: action.next, future: [] };
  }
  if (action.type === 'undo') {
    if (state.past.length === 0) return state;
    const present = state.past[state.past.length - 1];
    return {
      past: state.past.slice(0, -1),
      present,
      future: [state.present, ...state.future],
    };
  }
  if (action.type === 'redo') {
    if (state.future.length === 0) return state;
    const present = state.future[0];
    return {
      past: [...state.past, state.present],
      present,
      future: state.future.slice(1),
    };
  }
  return state;
}

export function useUndo<T>(initial: T) {
  const [state, dispatch] = useReducer(reducer<T>, { past: [], present: initial, future: [] });
  const set = useCallback((next: T) => dispatch({ type: 'set', next }), []);
  const undo = useCallback(() => dispatch({ type: 'undo' }), []);
  const redo = useCallback(() => dispatch({ type: 'redo' }), []);
  return {
    value: state.present,
    set,
    undo,
    redo,
    canUndo: state.past.length > 0,
    canRedo: state.future.length > 0,
  };
}
```

```tsx
// components/AgentRenamePanel.tsx
import { useUndo } from '../hooks/useUndo';

type FileMap = Record<string, string>; // path -> path

export function AgentRenamePanel({ initial }: { initial: FileMap }) {
  const { value, set, undo, canUndo } = useUndo<FileMap>(initial);

  async function applyAgentRenames(plan: FileMap) {
    const previous = value;
    set(plan); // optimistic
    try {
      await fetch('/api/rename', { method: 'POST', body: JSON.stringify(plan) });
    } catch (err) {
      set(previous); // server failed → automatic rollback
      throw err;
    }
  }

  return (
    <div>
      <RenameDiff before={value} />
      <button onClick={undo} disabled={!canUndo}>
        Undo last change
      </button>
    </div>
  );
}
```

The `set(previous)` on the catch branch is the *automatic* rollback (server-side failure); the explicit Undo button is the *user-driven* rollback (server succeeded but the user disagrees).

## Vue 3 — `pinia` undo store + persisted state

```ts
// stores/undo.ts
import { defineStore } from 'pinia';

export const useUndoStore = defineStore('undo', {
  state: () => ({
    past: [] as unknown[],
    present: null as unknown,
    future: [] as unknown[],
  }),
  actions: {
    set(next: unknown) {
      if (this.present !== null) this.past.push(this.present);
      if (this.past.length > 10) this.past.shift();
      this.present = next;
      this.future = [];
    },
    undo() {
      if (this.past.length === 0) return;
      this.future.unshift(this.present);
      this.present = this.past.pop();
    },
    redo() {
      if (this.future.length === 0) return;
      this.past.push(this.present);
      this.present = this.future.shift();
    },
  },
  persist: { storage: localStorage }, // pinia-plugin-persistedstate; survives reload
});
```

The `persist` plugin (`pinia-plugin-persistedstate`) writes the entire stack to `localStorage` on every mutation; refreshing the tab does not lose undo history.

## Svelte 5 — runes + persisted history

```svelte
<!-- src/lib/undoStore.svelte.ts -->
<script module lang="ts">
  const STORAGE_KEY = 'undo-stack-v1';

  function load<T>(): { past: T[]; present: T | null; future: T[] } {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) return JSON.parse(raw);
    } catch {}
    return { past: [], present: null, future: [] };
  }

  export function createUndoStore<T>() {
    const stored = load<T>();
    let past = $state<T[]>(stored.past);
    let present = $state<T | null>(stored.present);
    let future = $state<T[]>(stored.future);

    $effect(() => {
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify({ past, present, future }));
      } catch {}
    });

    return {
      get value() { return present; },
      get canUndo() { return past.length > 0; },
      get canRedo() { return future.length > 0; },
      set(next: T) {
        if (present !== null) past = [...past, present].slice(-10);
        present = next;
        future = [];
      },
      undo() {
        if (past.length === 0) return;
        future = [present!, ...future];
        present = past[past.length - 1];
        past = past.slice(0, -1);
      },
      redo() {
        if (future.length === 0) return;
        past = [...past, present!];
        present = future[0];
        future = future.slice(1);
      },
    };
  }
</script>
```

## Flutter — `Provider` + immutable state + `UndoState<T>`

```dart
// lib/undo/undo_state.dart
import 'package:flutter/foundation.dart';

@immutable
class UndoState<T> {
  final List<T> past;
  final T? present;
  final List<T> future;

  const UndoState({this.past = const [], this.present, this.future = const []});

  bool get canUndo => past.isNotEmpty;
  bool get canRedo => future.isNotEmpty;

  UndoState<T> setNext(T next) {
    final newPast = present == null
        ? past
        : ([...past, present as T].length > 10
            ? [...past, present as T].sublist(1)
            : [...past, present as T]);
    return UndoState(past: newPast, present: next, future: const []);
  }

  UndoState<T> undo() {
    if (past.isEmpty) return this;
    return UndoState(
      past: past.sublist(0, past.length - 1),
      present: past.last,
      future: present == null ? future : [present as T, ...future],
    );
  }

  UndoState<T> redo() {
    if (future.isEmpty) return this;
    return UndoState(
      past: present == null ? past : [...past, present as T],
      present: future.first,
      future: future.sublist(1),
    );
  }
}
```

```dart
// lib/undo/undo_controller.dart
import 'package:flutter/foundation.dart';
import 'undo_state.dart';

class UndoController<T> extends ChangeNotifier {
  UndoState<T> _state;
  UndoController(T initial) : _state = UndoState<T>(present: initial);

  T? get value => _state.present;
  bool get canUndo => _state.canUndo;
  bool get canRedo => _state.canRedo;

  void set(T next) { _state = _state.setNext(next); notifyListeners(); }
  void undo() { _state = _state.undo(); notifyListeners(); }
  void redo() { _state = _state.redo(); notifyListeners(); }
}
```

For cross-session persistence, layer `shared_preferences` on top: serialize `_state` to JSON in `notifyListeners()` and rehydrate in the constructor.

## SwiftUI — `@Observable` + history array + `SecureStore`

```swift
// UndoStore.swift
import Observation
import Foundation

@Observable
final class UndoStore<Value: Codable & Equatable> {
    private(set) var past: [Value] = []
    private(set) var present: Value?
    private(set) var future: [Value] = []

    private let storageKey = "undo-stack-v1"

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    init(initial: Value? = nil) {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let restored = try? JSONDecoder().decode(Snapshot<Value>.self, from: data) {
            self.past = restored.past
            self.present = restored.present
            self.future = restored.future
        } else {
            self.present = initial
        }
    }

    func set(_ next: Value) {
        if let p = present { past.append(p); if past.count > 10 { past.removeFirst() } }
        present = next
        future = []
        persist()
    }

    func undo() {
        guard let p = past.popLast() else { return }
        if let curr = present { future.insert(curr, at: 0) }
        present = p
        persist()
    }

    private func persist() {
        let snap = Snapshot(past: past, present: present, future: future)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

private struct Snapshot<V: Codable>: Codable {
    let past: [V]
    let present: V?
    let future: [V]
}
```

For credentials / PII the operator should swap `UserDefaults` for `Keychain` via `SecureStore`-style helpers. The contract is identical.

## Persistence size cap

| Platform | Storage | Suggested cap |
|---|---|---|
| Web | `localStorage` | 10 entries × ≤ 50 KB serialized; LRU evict |
| Web (privacy-sensitive) | `IndexedDB` | 10 entries × ≤ 1 MB |
| Mobile (non-PII) | `shared_preferences` / `UserDefaults` | 10 entries × ≤ 50 KB |
| Mobile (PII / secrets) | `Keychain` / `flutter_secure_storage` | 5 entries × ≤ 10 KB |

The hard rule: always cap. Unbounded undo stacks corrupt every storage backend eventually.

## Show what changed — the diff view

The undo button alone is half the contract. The user must also see *what* will be reverted. Render a diff panel adjacent to the undo button:

```tsx
<RenameDiff
  before={prevState}
  after={currentState}
  showAffectedCount
/>
<button onClick={undo}>Undo last change ({diffCount} files)</button>
```

For text fields, use `diff-match-patch` or `jsdiff`. For structural changes (nested objects), render the changed paths as a tree.

## Anti-patterns to avoid

| Anti-pattern | Why it fails |
|---|---|
| Destructive op with no undo button | Trust contract violated |
| Undo button without showing what changed | User has to guess what will revert |
| Unbounded undo stack growth | Storage corruption / memory leaks |
| Persistence in plaintext for PII fields | Privacy / compliance breach |
| Undo only available within the same session | Real mistakes are caught after refresh |
| `confirm("Delete?")` then permanent state mutation | One-stage flow with no escape |
| Single global undo stack mixing unrelated flows | Undo from "rename files" reverts your "save preferences" |

## Citations

- [React `useReducer` reference](https://react.dev/reference/react/useReducer)
- [Pinia persisted state plugin](https://prazdevs.github.io/pinia-plugin-persistedstate/)
- [Svelte 5 runes overview](https://svelte.dev/docs/svelte/what-are-runes)
- [Flutter `ChangeNotifier`](https://api.flutter.dev/flutter/foundation/ChangeNotifier-class.html)
- [SwiftUI `@Observable`](https://developer.apple.com/documentation/observation/observable())
- [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)
