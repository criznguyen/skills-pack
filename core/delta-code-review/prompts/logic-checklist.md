# Logic checklist — BLOCK and SUGGEST findings

Apply this checklist FIRST, before `prompts/style-checklist.md`. These rules surface correctness, security, and meaningful-quality findings. Severity is BLOCK when the change could produce wrong output, expose data, or break a contract. Severity is SUGGEST when the change is correct but a meaningful improvement is available.

## Scope

We are reviewing a unified `git diff`. We focus on what the `+` lines do and how they interact with the surrounding context lines. We do NOT re-architect the system. We do NOT request additional files. If a `+` line references a symbol genuinely undefined within the diff window, emit `category: undefined-reference` and continue.

## BLOCK candidates — correctness, security, contract

### 1. Comparator and ordering bugs

- Sort comparator returns `a - b` where `a` and `b` may be strings, dates-as-strings, or non-numeric — string subtraction yields `NaN`, sort order undefined.
  - **Suggested fix shape:** `localeCompare` for strings, `Number(a) - Number(b)` only after explicit numeric conversion, `(a, b) => a < b ? -1 : a > b ? 1 : 0` for general comparable.
- Comparator returns boolean (`a > b`) instead of `-1 | 0 | 1` — V8 tolerates it but other engines don't.
- Sort key recomputed inside the comparator (O(n log n) extra work) — usually SUGGEST, BLOCK only if the recomputed key has side effects.

`category: logic-bug`. BLOCK.

### 2. Off-by-one and boundary

- Loop bound uses `<=` where `<` is intended (or vice versa), and the index is used to access an array.
- Slice / substring with a bound that excludes the last element silently.
- Pagination skip/limit math that drops or duplicates an item at the page boundary.

`category: logic-bug`. BLOCK.

### 3. Null / undefined / falsy traps

- `if (x)` where `x` could legitimately be `0` or `""` and zero/empty is a valid value.
- Optional chaining `a?.b.c` (chain stops at `?.` then re-asserts) — should be `a?.b?.c`.
- Default parameter or `||` fallback where `??` is correct.
- Dereferencing a value just returned from `.find()` / `Map.get()` without a null check.

`category: logic-bug`. BLOCK if a realistic input triggers it; SUGGEST if defensive only.

### 4. Async / concurrency

- Missing `await` on a Promise-returning call whose result is used.
- `Promise.all` with a side-effecting callback that mutates shared state without ordering guarantees.
- Reading then writing shared state across an `await` boundary without re-validation.
- `forEach` with an `async` callback (the outer caller doesn't wait).

`category: concurrency`. BLOCK.

### 5. Error handling

- `catch (e) {}` empty block — silently swallows.
- `catch (e) { console.log(e) }` and continues as if success.
- Throwing a string or plain object instead of an `Error`.
- Re-thrown error loses cause / stack (catch-and-throw-new without `cause`).
- Unwrap / `!` / `unwrap()` on a value that can legitimately be absent.

`category: error-handling`. BLOCK on swallow / wrong-error; SUGGEST on lost-cause.

### 6. Security

- SQL string concatenation with any value not provably constant.
- Shell-out with user-controllable args and no shell-quoting.
- `eval` / `Function(string)` / `new Function` on input.
- Credential / token / secret literal in source (any high-entropy string assigned to a name like `*_KEY`, `*_TOKEN`, `*_SECRET`, `password`, `apiKey`).
- Logging a request body / headers without redaction in code that looks production-bound.
- Disabled SSL verification, hardcoded `Bearer` tokens, weak crypto (`MD5`, `SHA1` for password / signature).
- Path traversal: file path built from input without normalization / containment check.

`category: security`. BLOCK.

### 7. API / contract changes

- Public function signature changed (param added / removed / reordered) without obvious caller updates in the diff.
- Enum value renamed / removed.
- JSON serialization shape changed (key renamed, optional made required).
- HTTP route or method changed.
- Database column type narrowed without migration.

`category: api-contract`. BLOCK.

### 8. Data-loss and destructive ops

- `rm -rf`, `DROP TABLE`, `TRUNCATE`, `git push --force`, `git reset --hard` introduced in source (not just docs / examples).
- File deletion without backup or confirmation in a flow that can be triggered from input.

`category: security` (or `logic-bug` if not security-relevant). BLOCK.

## SUGGEST candidates — non-blocking improvements

### 9. Missing test for the new branch

- A new conditional branch is added but no test in the diff exercises it.
- A new public function is added but no test in the diff calls it.

`category: missing-test`. SUGGEST. (Not BLOCK — `tdd-red-green` is the place for hard test-gating.)

### 10. Dead or unreachable code

- A new `if` whose condition can never be true given immediately-prior code.
- An `else` after an early-return.
- An exported symbol with no caller anywhere visible in the diff (may be a real export — keep SUGGEST).

`category: dead-code`. SUGGEST.

### 11. Redundant / wasteful work

- Recomputing the same value inside a tight loop.
- Allocating a new array / object inside a comparator or hot loop.
- Reading from disk / network in a place that looks like a hot path.

`category: other`. SUGGEST.

### 12. Type narrowing missed

- `any` introduced where a concrete type is available.
- A union type where one branch is provably impossible at the call site but not narrowed.
- Generics with no constraint where a constraint would prevent misuse.

`category: idiom`. SUGGEST.

### 13. Simpler primitive available

- Hand-rolled deep-clone where `structuredClone` is available.
- Hand-rolled debounce / retry where the project clearly already imports a utility.
- `for...of` accumulation where `.reduce` or `.flatMap` expresses intent more clearly.

`category: idiom`. SUGGEST.

### 14. Error message will not help debugging

- `throw new Error("failed")` with no context.
- Error includes raw user input but no operation name / id.

`category: error-handling`. SUGGEST.

## Promotion rules

- **SUGGEST -> BLOCK**: only if you can name a realistic input or sequence that produces wrong output, exposed data, or a contract break. "It might be wrong" is not enough.
- **BLOCK -> SUGGEST**: only if the surrounding context lines clearly preempt the failure mode (e.g., the value is provably constant, validated upstream in the diff window).

## Demotion rule

If a SUGGEST candidate is genuinely cosmetic and "next 6 months wouldn't bite us," demote to NIT under `prompts/style-checklist.md` instead.

## Output contract

Every finding here MUST conform to `schemas/comment.json` with `severity` BLOCK or SUGGEST. NITs go through the style checklist, not this one.
