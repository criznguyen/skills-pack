# Style checklist — NIT-tier findings

Apply this checklist AFTER `prompts/logic-checklist.md`. These rules surface NIT-severity findings only. None of these should ever be promoted to BLOCK. If a "style" issue feels like it might cause a bug, the issue is logic, not style — re-classify under `prompts/logic-checklist.md` instead.

## Scope

Style is local-readability, not architecture. We are not refactoring. We are flagging things a reviewer would write a one-line PR comment about.

## Checklist (each item -> a candidate NIT)

### 1. Naming consistency

- New symbol introduces a name that conflicts with the file's existing convention (camelCase vs snake_case, `is*` vs `has*`).
- Variable name is single-letter where the surrounding code uses descriptive names.
- Function name says "manager" / "helper" / "utils" with no domain word.

`category: naming` — only NIT. (Misleading names that imply wrong behavior are `logic-bug`, BLOCK.)

### 2. Imports

- Import is unused (the diff added it but nothing in the diff references it).
- Import order broken from the file's prior convention (alphabetical / grouped / etc).
- Wildcard import where the file otherwise uses explicit imports.

`category: style` or `category: idiom`.

### 3. Whitespace and formatting

- Trailing whitespace on `+` lines.
- Mixed tabs/spaces in a tab-only or space-only file.
- Excess blank lines (>1 consecutive blank inside a function body).
- Line length exceeds the project's apparent ceiling by a wide margin (only flag if the file's other lines wrap, i.e., a project convention is visible).

`category: style`. NIT only.

### 4. Idiomatic alternatives

- `for (let i = 0; i < arr.length; i++)` where `for...of` would read cleaner and the index is unused.
- `.filter(x => x).map(...)` where `.flatMap` or `.reduce` would express intent more directly — only flag if the surrounding code uses functional style.
- `if (x === true)` / `if (x === false)` where `if (x)` / `if (!x)` is idiomatic for booleans.
- Manual `Promise.then` chains inside an `async` function where `await` is in scope.
- String concatenation where the file otherwise uses template literals.

`category: idiom`. NIT only.

### 5. Comments

- New comment restates the code (`// increment i`).
- New TODO with no owner / no ticket.
- Stale comment now contradicts the code it documents (the diff changed the code but not the comment above it).

`category: style`. NIT only — except a stale comment that promises a contract the code now violates is `api-contract` BLOCK.

### 6. Test placement

- New test added but placed in a file inconsistent with the project's test layout (e.g., `foo.test.ts` next to `foo.ts` when the project uses `__tests__/`).

`category: style`. NIT.

## What this checklist does NOT cover

- Logic bugs, comparator errors, off-by-one — `prompts/logic-checklist.md`.
- Security — `prompts/logic-checklist.md` (security category).
- Architecture, naming-of-modules, file-tree shape — `audit` (P0-02).

## Promotion rule

If a single style finding "feels" like it deserves SUGGEST, ask: would skipping this fix risk a bug in the next 6 months? If no, keep it NIT. If yes, re-classify under `prompts/logic-checklist.md` and bump severity.

## Output contract

Each item flagged here MUST be `severity: NIT` and conform to `schemas/comment.json`.
