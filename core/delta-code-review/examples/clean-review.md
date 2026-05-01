# Example: clean diff -> empty review

This example shows the expected output of `delta-code-review` on a small, clean diff with no findings. The point of the example is to demonstrate that the skill emits `[]` and a zero-summary line, NOT to invent findings to look thorough. Failing this shape is what the regression test in `tests/tasks.yaml` (task `clean-no-findings`) catches.

## Input diff (~50 LOC)

```diff
diff --git a/src/string-utils.ts b/src/string-utils.ts
index 1234567..89abcde 100644
--- a/src/string-utils.ts
+++ b/src/string-utils.ts
@@ -1,4 +1,12 @@
 export function trimEnds(input: string): string {
   return input.trim();
 }
+
+/** Returns the input with the first character upper-cased. */
+export function capitalize(input: string): string {
+  if (input.length === 0) {
+    return input;
+  }
+  return input.charAt(0).toUpperCase() + input.slice(1);
+}
diff --git a/tests/string-utils.test.ts b/tests/string-utils.test.ts
index 4444444..5555555 100644
--- a/tests/string-utils.test.ts
+++ b/tests/string-utils.test.ts
@@ -1,7 +1,17 @@
-import { trimEnds } from '../src/string-utils';
+import { trimEnds, capitalize } from '../src/string-utils';

 describe('trimEnds', () => {
   it('trims spaces', () => {
     expect(trimEnds('  hi  ')).toBe('hi');
   });
 });
+
+describe('capitalize', () => {
+  it('capitalizes the first character', () => {
+    expect(capitalize('hello')).toBe('Hello');
+  });
+
+  it('handles empty string', () => {
+    expect(capitalize('')).toBe('');
+  });
+});
```

## Walk-through

1. Resolve diff range. ~22 LOC added across 2 files. Well under the 200 LOC threshold.
2. Apply `prompts/logic-checklist.md`:
   - Comparator bugs: none.
   - Off-by-one / boundary: empty-string branch is handled correctly.
   - Null / falsy traps: `if (input.length === 0)` is explicit; not a falsy trap.
   - Async / concurrency: none — fully synchronous.
   - Error handling: not applicable.
   - Security: no input from network / shell / sql.
   - Contract changes: a new export is added, but no existing signature is touched.
   - Data-loss: none.
   - Missing test: tests are added in the same diff, covering both branches.
3. Apply `prompts/style-checklist.md`:
   - Naming: `capitalize` matches existing `trimEnds` camelCase convention.
   - Imports: updated correctly.
   - Whitespace: clean.
   - Idioms: nothing to flag.
   - Comments: JSDoc is informative, not redundant.
4. Empty findings array.

## Expected output

```json
[]
```

```
0 BLOCK / 0 SUGGEST / 0 NIT across 0 files
```

## What this example proves

- The skill does NOT invent findings to appear diligent.
- A new public export with co-located tests in the same diff is acceptable — `missing-test` does not fire.
- A guard clause (`if (input.length === 0)`) is treated as evidence the author thought about the boundary, not as a redundant branch worth flagging.
- The summary line is emitted even when the array is empty.
