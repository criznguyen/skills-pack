# Example: 150-LOC diff -> 3 findings (1 BLOCK, 1 SUGGEST, 1 NIT)

This example shows the expected output of `delta-code-review` on a moderately-sized diff that contains one real correctness bug, one missing-test, and one style nit. The shape demonstrates the multi-tier severity output and the `suggested_fix` field.

## Input diff (~150 LOC)

```diff
diff --git a/src/sort.ts b/src/sort.ts
index 0000000..1111111 100644
--- a/src/sort.ts
+++ b/src/sort.ts
@@ -1,8 +1,42 @@
 export type User = { id: string; name: string; createdAt: string };

 export function sortById(users: User[]): User[] {
-  return [...users].sort((a, b) => a.id.localeCompare(b.id));
+  return [...users].sort((a, b) => a.id.localeCompare(b.id));
 }
+
+export function sortByName(users: User[]): User[] {
+  // BUG: comparator uses string subtraction; result is NaN, sort order undefined.
+  return [...users].sort((a, b) => a.name - b.name);
+}
+
+export function sortByCreatedAt(users: User[]): User[] {
+  // Sort newest-first by ISO timestamp string.
+  return [...users].sort((a, b) => {
+    if (a.createdAt < b.createdAt) return 1;
+    if (a.createdAt > b.createdAt) return -1;
+    return 0;
+  });
+}
+
+export function indexById(users: User[]): Map<string, User> {
+  const out = new Map<string, User>();
+  for (let i = 0; i < users.length; i++) {
+    const u = users[i];
+    out.set(u.id, u);
+  }
+  return out;
+}
diff --git a/tests/sort.test.ts b/tests/sort.test.ts
index 2222222..3333333 100644
--- a/tests/sort.test.ts
+++ b/tests/sort.test.ts
@@ -1,5 +1,18 @@
-import { sortById } from '../src/sort';
+import { sortById, sortByCreatedAt, indexById } from '../src/sort';

 describe('sortById', () => {
   it('sorts ascending by id', () => {
     /* ... existing test unchanged ... */
   });
 });
+
+describe('sortByCreatedAt', () => {
+  it('sorts newest first', () => {
+    /* ... */
+  });
+});
+
+describe('indexById', () => {
+  it('keys by id', () => {
+    /* ... */
+  });
+});
```

## Walk-through

1. Resolve diff range. ~150 LOC added across 2 files. Within budget.
2. Apply `prompts/logic-checklist.md`:
   - **Comparator bugs:** `sortByName` uses `a.name - b.name` where `name` is a string. String subtraction yields `NaN`. Sort order is undefined. **BLOCK.**
   - **Missing test:** `sortByName` is exported but has no test in the diff. The other three new exports do. **SUGGEST.**
   - All other logic checks: pass.
3. Apply `prompts/style-checklist.md`:
   - `indexById` uses `for (let i = 0; i < users.length; i++)` where `i` is unused after `users[i]`. `for...of` would be more idiomatic. **NIT.**
   - All other style checks: pass.

## Expected output

```json
[
  {
    "file": "src/sort.ts",
    "line_range": "10-12",
    "severity": "BLOCK",
    "category": "logic-bug",
    "comment": "Comparator `(a, b) => a.name - b.name` performs subtraction on strings, yielding NaN. Array.sort treats NaN as 'no swap', so the resulting order is implementation-defined and effectively random.",
    "suggested_fix": "Replace with `(a, b) => a.name.localeCompare(b.name)`. Add a test case `sortByName([{name:'c'},{name:'a'},{name:'b'}])` that asserts the alphabetical result."
  },
  {
    "file": "src/sort.ts",
    "line_range": "10-12",
    "severity": "SUGGEST",
    "category": "missing-test",
    "comment": "`sortByName` is a new public export but has no test in this diff; the other three new exports do. Adding even one happy-path case prevents regression.",
    "suggested_fix": "Add a `describe('sortByName', ...)` block to `tests/sort.test.ts` with at least one assertion against a known-good ordering."
  },
  {
    "file": "src/sort.ts",
    "line_range": "29-32",
    "severity": "NIT",
    "category": "idiom",
    "comment": "`for (let i = 0; i < users.length; i++)` uses an index that is only dereferenced once; `for...of` reads cleaner and matches the file's surrounding functional style.",
    "suggested_fix": "Replace with `for (const u of users) { out.set(u.id, u); }`."
  }
]
```

```
1 BLOCK / 1 SUGGEST / 1 NIT across 1 files
```

## What this example proves

- One BLOCK finding does not suppress the SUGGEST and NIT findings — the review surfaces all severities in one pass.
- The same `file:line_range` can carry two findings of different severity (the BLOCK comparator and the SUGGEST missing-test for the same export). Both are emitted; deduplication keeps highest severity ONLY when the category and root cause are identical.
- `suggested_fix` is concrete code, not advice.
- The summary line counts findings, not files-with-findings (it reports `1 BLOCK / 1 SUGGEST / 1 NIT across 1 files`, where the `1 files` is distinct files touched by findings).
