# governance-pack — debug-tag convention

Sourced from `mattpocock/skills/engineering/diagnose/SKILL.md` Phase 4
line 85 (MIT — see `NOTICES.md` at repo root for the verbatim
permission notice and upstream attribution).

This page is operator-facing documentation. The load-bearing
enforcement lives in `core/governance-pack/hooks/telemetry.sh`
(`_check_debug_tags()`) and the CI grep
— see §4 below. Charter §2.2 (hooks-over-rules): the convention is
hook-enforced, not prose-enforced.

## 1. Canonical literal

Every agent-emitted debug log carries `[DEBUG-<HEX>]` where `<HEX>` is
exactly 8 lowercase hex chars matching `[0-9a-f]{8}`. Hex may be
deterministic (e.g. `sha256(spec_id)[:8]`) or random per session —
both are accepted. Cleanup is global (single grep across the tree),
so collisions are tolerable.

Canonical regex: `\[DEBUG-[0-9a-f]{8}\]`. This regex is copied
verbatim into three sites — this file (§1), `telemetry.sh`
(`tag_re=`), and `skills-eval.yml` (`debug-tag-cleanup-warn` step).
Any drift surfaces within one PR cycle (each copy is exercised every
session / every push).

## 2. Why

Charter §2.5 names verifiability the highest-leverage governance
input. A tagged debug log makes cleanup a single grep — the failure
mode (forgotten `console.log` surviving into commits) becomes
impossible to miss because the literal is grep-able by definition.
The tag is for *agent-emitted ephemeral instrumentation only*;
production logging, audit-report content, and telemetry JSONL are
out of scope (see spec NG4).

## 3. Operator workflow

When you scatter a debug log, prefix the message with the literal:

    console.log("[DEBUG-a4f2c1d9] state=" + JSON.stringify(state));
    print(f"[DEBUG-a4f2c1d9] payload={payload!r}")
    eprintln!("[DEBUG-a4f2c1d9] err={:?}", err);
    fmt.Println("[DEBUG-a4f2c1d9] resp=", resp)

Cleanup before commit (the §2.5 single-grep win):

    grep -RlE '\[DEBUG-[0-9a-f]{8}\]' . | \
      xargs -r sed -i.bak '/\[DEBUG-[0-9a-f]\{8\}\]/d' && \
      find . -name '*.bak' -delete

Seed pattern catalogue (the strings the hook scans for when no tag
is present): `console.(log|error|warn|debug|info)(`, `print(`,
`dbg!(`, `eprintln!(`, `println!(`, `fmt.Println(`. Ruby `puts`,
PHP `var_dump`, etc. are not in the seed list — they will be added
when a real operator hits the gap (charter §7 "lessons →
D5).

## 4. Enforcement (charter §2.2 — hook, not prose)

Two layers, both warn-only (exit 0 always):

1. `core/governance-pack/hooks/telemetry.sh` ships
   `_check_debug_tags()`, fired on PostToolUse for the tools
   `Bash`, `Edit`, `Write`. The function emits a single stderr line
   prefixed `debug-tag:` when (a) tool input contains a debug-class
   string with no same-line `[DEBUG-<8-hex>]` tag, or (b) the tool
   is `Bash` invoking `git commit` and `git diff --cached` still
   shows `[DEBUG-` in the staged diff. Always returns 0.
2. CI parallel: `debug-tag-cleanup-warn` in
   on every PR and push to main, emitting `::warning file=,line=::`
   annotations on any non-fixture file containing the tag. Excludes
   own SDLC docs, and this CLAUDE.md (see spec NG6). Always exits 0.

This file performs NO runtime check. It is documentation only.

## 5. Opt-out

    export GOVERNANCE_PACK_DEBUG_TAG_CHECK=0   # silence local hook warns

The CI grep does not respect `GOVERNANCE_PACK_DEBUG_TAG_CHECK` —
forgotten tags still surface as PR-checks `::warning::` annotations
regardless of local environment, so reviewers see the signal even
when an operator has muted their session.

## 6. Uninstall

1. Set `GOVERNANCE_PACK_DEBUG_TAG_CHECK=0` in your shell (silences
   the hook immediately) OR delete the `_check_debug_tags` function
   and its call site from `core/governance-pack/hooks/telemetry.sh`
   for a permanent local removal.
2. Drop the `debug-tag-cleanup-warn` job from
   `needs:` arrays of `per-skill-tests` and `smoke`.
3. Delete this file plus

## 7. Postcondition convention (charter §2.1 — verify-before-claim)

After every state-changing tool call, the
`core/governance-pack/hooks/postcondition-hook.sh` PostToolUse hook
walks `~/.claude/postconditions.d/*.sh` and asserts the world matches
the claim. The convention is hook-enforced, not prose-enforced — this
section is operator-facing documentation for *reading* the telemetry,
not the source-of-truth for the rule. See README.md
"Phase 2.1 enforcement (postcondition hook)" for the install + mode
+ authoring details.

The hook is **shadow-mode** for the first 30 days post-install: every
fail emits a JSONL line + an advisory stderr line, but the agent
proceeds (exit 0). To audit the run after a session:

    jq 'select(.event=="postcondition" and .status!="pass")' \
      ~/.claude/telemetry.jsonl | tail -50

When the FP rate looks <5% on your project's golden eval, promote the
gate to blocking with the one-line `jq` edit documented in README.md
§"Mode (shadow vs blocking)". DO NOT promote on day 1; the FP rate
of an unfamiliar postcondition table is unknowable until evidence
accumulates (F2-7).

### Forbidden content in postconditions.d/*.sh (TM5 / NG4)

NO LLM invocation. NO sub-agent spawn. NO `claude -p`, `Agent(`,
`anthropic.`, `@anthropic`. Postconditions are deterministic shell
ONLY; semantic verification is the audit sub-agent's job (charter
§2.3 independence-of-reviewer). The `_self.sh` default flags
bare-`exit 0` postcondition Edits; the `system-change:` audit
checklist greps for the forbidden literals in any change to the
templates dir.

## 8. Recovery-class advisory (opt-in, no charter touch)

`core/recovery-class-fragment/` ships an opt-in PostToolUse hook
(matcher `Bash|Edit|Write`) that classifies non-empty `tool_response.stderr`
into a 4-class taxonomy (`transient` / `config-drift` / `logic-error` /
`external-failure`) by case-insensitive substring match against
`templates/recovery-classes.tsv`. When exactly ONE class matches the
hook surfaces a single-line `[RECOVERY-HINT: class=<class> action=<primitive>]`
advisory through `hookSpecificOutput.additionalContext` so the next
turn's context carries the recovery-primitive suggestion. Multi-class
matches stay silent (silence > guess).

This skill is **not** auto-installed by `governance-pack/install.sh` —
the operator wires it themselves (see
`core/recovery-class-fragment/README.md` §Install). Charter §2.2 prose
already covers hooks-over-rules; an opt-in advisory hint does not need
its own charter clause (research final report §5 P1 #4 ROW: NO charter
touch).

Forbidden in `core/recovery-class-fragment/hooks/*.sh`: same TM4 list as
above (`claude -p`, `Agent(`, `anthropic.`, `@anthropic`). Enforced by
`core/recovery-class-fragment/tests/test-no-claude-spawn.sh`.

End of `core/governance-pack/CLAUDE.md`.
