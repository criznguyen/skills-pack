# core-config baseline

Drop-in CLAUDE.md for `~/.claude/` (global) or `<repo>/.claude/` (project).
Sections are load-bearing — do not reorder. Section 8 is the canonical task-class
rubric; keep it verbatim.

## 1. Anti-fantasy rules
- If a file/function/symbol is referenced and you have not read it, read it first.
- Never propose a diff against a file you have not read in this turn.
- If a fact is not in the codebase or in tool output, say "I don't know" — do not invent.
- Before claiming a library/API/flag exists, verify via docs, --help, or grep.
- Read the file again before applying a patch.

## 2. Verification rule
- Every task ends with a `make verify` (or repo-equivalent) run.
- "Done" means verify exited 0. Not "I think it's done."
- If verify fails, address root cause. Do NOT suppress errors.

## 3. Plan-mode default
- For any task touching >1 file or unfamiliar code: Plan Mode first.
- Skip the plan only if you can describe the diff in one sentence.

## 4. Compaction preservation
- On /compact, preserve: modified-files list, test commands, unresolved decisions, current spec hash.

## 5. Solo-dev git rules
- Commit to main. Conventional-commit prefixes. No Co-Authored-By trailer.
- Author = criznguyen always.

## 6. Sub-agent isolation rule
- Audits run in a fresh sub-agent context with diff + spec only — never main thread.

## 7. Verification-before-recall
- Memory recall is a CLAIM, not a fact. Glob/Grep before acting on it.

## 8. Task class — pick one before starting (read the rubric):
- trivial: <5 LoC, no behavior change, no public-API change → skip plan, just do it
- small: 1-3 files, 1 module, no contract change → Plan Mode, then implement
- system-change: production-touching, contract-breaking, or security-critical → full pipeline (phases 4-10c) (audit REQUIRED, same artifact rule)

Upgrade triggers: discovered new contract change, discovered security-critical path, blast radius beyond initial estimate.
Downgrade triggers: discovery showed the "feature" was a config tweak, no behavior change after spec'ing.

## 9. Idea-evaluation gate
Before adding a dep / pattern / service / architectural change: read `core/core-config/templates/idea-rubric.md` and produce a VERDICT block in `decisions.md`.
