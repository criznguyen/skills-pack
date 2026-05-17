---
name: recovery-class-fragment
description: Opt-in error-recovery classifier. PostToolUse hook on `Bash|Edit|Write` matches `tool_response.stderr` against a 4-class taxonomy (transient / config-drift / logic-error / external-failure) and surfaces a `[RECOVERY-HINT: class=<class> action=<primitive>]` advisory via `hookSpecificOutput.additionalContext`. Charter §2.2 hooks-over-rules. Operator opts in by editing `~/.claude/settings.json` — no charter touch (v2.0 P1 #4).
paths: []
when_to_use: Read-only reference taxonomy + opt-in PostToolUse classifier; never invoked directly as a slash command.
disable-model-invocation: true
type: governance
tools: Bash, Read, Grep, Glob
model: opus
auto_trigger: false
blast_radius: read-only
last-validated: 2026-04-29
---

# recovery-class-fragment

Opt-in error-recovery taxonomy. When a state-changing tool call (`Bash`, `Edit`, `Write`) returns non-empty stderr, the operator-installed PostToolUse hook (`hooks/recovery-classify.sh`) matches the stderr text against a 4-class TSV table (`templates/recovery-classes.tsv`) and emits a single `[RECOVERY-HINT: ...]` advisory through `hookSpecificOutput.additionalContext` so the next-turn context carries a class+primitive hint.

**The hook is shell + jq + python3 fallback only — no LLM, no sub-agent.** Pure keyword matching against the TSV; classifier confidence ≥0.8 (single-class match) is required before emitting a hint. Multi-class matches are suppressed (we trust silence over noise).

## When to use

- Long sessions where transient errors (rate limits, timeouts) and config-drift (missing env vars, stale tokens) repeatedly surface.
- Operators who want a deterministic recovery-primitive suggestion in the next turn ("retry / surface-and-ask / fix-implementation / escalate-to-human") without paying for a separate LLM classification round-trip.

## When NOT to use

- **As a structural defense.** Like quarantine-pack, this hook fires AFTER the model has ingested the raw tool result. The hint lands one turn later and is advisory only. The hook never blocks — it always exits 0.
- **For semantic root-cause analysis.** The 4-class TSV is keyword-shallow on purpose (charter §2.3 — semantic verification is the audit sub-agent's job, not a runtime hook). If your error stream needs a real diagnosis, use the audit skill, not this hook.
- **Silent default.** The hook is `auto_trigger: false`. It does NOT auto-install through `governance-pack/install.sh`. The operator opts in by editing `~/.claude/settings.json` themselves (see Install).

## The 4-class taxonomy

| Class | Recovery primitive | When |
|---|---|---|
| `transient` | retry-with-backoff | rate limits, network timeouts, lock contention |
| `config-drift` | surface-and-ask | missing env vars, expired tokens, stale config |
| `logic-error` | fix-implementation | TypeError, AssertionError, contract violation |
| `external-failure` | escalate-to-human | upstream 5xx, hardware failure, service down |

Full table with example error patterns lives in `templates/recovery-classes.tsv` (TSV format, hand-editable).

## Install

This is an opt-in skill — `core/governance-pack/install.sh` does NOT auto-wire it. To enable:

```bash
# 1. Copy the hook to the install dest.
mkdir -p ~/.claude/hooks/recovery-class-fragment
cp core/recovery-class-fragment/hooks/recovery-classify.sh ~/.claude/hooks/recovery-class-fragment/
cp core/recovery-class-fragment/templates/recovery-classes.tsv ~/.claude/hooks/recovery-class-fragment/

# 2. Register the PostToolUse matcher.
jq '.hooks.PostToolUse += [{
  "matcher": "Bash|Edit|Write",
  "hooks": [{"type":"command","command":"'$HOME'/.claude/hooks/recovery-class-fragment/recovery-classify.sh","timeout":5000}]
}]' ~/.claude/settings.json | sponge ~/.claude/settings.json
```

Per-session disable:

```bash
export RECOVERY_CLASS_FRAGMENT_DISABLE=1
```

## Uninstall

Drop the matcher entry from `~/.claude/settings.json` and remove `~/.claude/hooks/recovery-class-fragment/`. There is no operator-owned data to purge.

## Forbidden in hook bodies (TM4)

`hooks/recovery-classify.sh` MUST NOT contain LLM-spawn literals. Enforced by `tests/test-no-claude-spawn.sh`. Hook is shell + jq + python3-fallback + grep only.

## Why no charter touch

Per research final report §5 (P1 #4 row), the recovery-class fragment rides existing §2.2 hooks-over-rules prose. The charter does not need a per-feature paragraph for every hook; the §2.2 mechanism already covers "deterministic enforcement beats prose enforcement," and a 30-line cross-link in `core/governance-pack/CLAUDE.md` is the shape that fits this opt-in convention.

## References

- Final report v2.0 plan: [`docs/research/harness-skills-required/00-final-report.md`](../../docs/research/harness-skills-required/00-final-report.md) §5 P1 #4
- Cross-link from governance-pack: [`core/governance-pack/CLAUDE.md`](../governance-pack/CLAUDE.md)
- Charter §2.2 hooks-over-rules: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
