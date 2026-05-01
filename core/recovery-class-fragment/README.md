# `recovery-class-fragment` — opt-in error-recovery classifier

v2.0 P1 #4. Charter §2.2 hooks-over-rules; **no charter touch** per research final report §5.

> **Mechanism.** A PostToolUse hook reads `tool_response.stderr`, matches against a 4-class taxonomy TSV, and surfaces a `[RECOVERY-HINT: class=<class> action=<primitive>]` advisory in the next turn's context. Single-class match (confidence ≥0.8) only — multi-class matches stay silent. No LLM. No sub-agent. Always exits 0.

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body; opt-in convention. |
| `CLAUDE.md` | The classifier *fragment* — copy-paste prose for skill authors who want the taxonomy reference inline. |
| `hooks/recovery-classify.sh` | PostToolUse(`Bash\|Edit\|Write`). Reads stderr, runs TSV match, emits hint. |
| `templates/recovery-classes.tsv` | The 4-class table — `class<TAB>recovery-primitive<TAB>example-error-pattern<TAB>example-action`. Hand-editable. |
| `tests/test-recovery-classify.sh` | 5-case unit suite (one synthetic error per class + a multi-class suppression case). |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |
| `examples/sample-output.jsonl` | 3-line synthetic JSONL sample (privacy-clean). |

## The 4 classes

| Class | Primitive | Stderr signals |
|---|---|---|
| `transient` | `retry-with-backoff` | `rate limit`, `429`, `timeout`, `temporary failure`, `try again` |
| `config-drift` | `surface-and-ask` | `not found in environment`, `permission denied`, `unauthorized`, `invalid token`, `expired` |
| `logic-error` | `fix-implementation` | `TypeError`, `AssertionError`, `NullPointerException`, `undefined`, `not callable` |
| `external-failure` | `escalate-to-human` | `502`, `503`, `504`, `connection refused`, `service unavailable`, `internal server error` |

Confidence rule: a single-class match emits the hint; two or more class matches in the same stderr emits *nothing* (the hook prefers silence over guessing). The TSV is operator-editable; add patterns by appending rows.

## Why opt-in (and why no charter touch)

Per the v2.0 research final report §5 row "P1 #4 recovery-class-fragment": the fragment rides existing §2.2 mechanism prose. Charter-grade enforcement of an *advisory hint* would be over-promotion — the charter is reserved for primitives whose absence collapses a load-bearing principle (§2.1 anti-fantasy, §2.2 hooks-over-rules, §2.3 reviewer independence, §2.4 vendor coordination, §2.5 verifiability). A recovery hint is operator-scoped ergonomics; it lives in `governance-pack/CLAUDE.md` as a 30-line cross-link, not in the charter.

## Install

```bash
mkdir -p ~/.claude/hooks/recovery-class-fragment
cp core/recovery-class-fragment/hooks/recovery-classify.sh ~/.claude/hooks/recovery-class-fragment/
cp core/recovery-class-fragment/templates/recovery-classes.tsv ~/.claude/hooks/recovery-class-fragment/
chmod +x ~/.claude/hooks/recovery-class-fragment/recovery-classify.sh

# Register matcher (jq required):
TMP=$(mktemp)
jq '.hooks.PostToolUse += [{
  "matcher": "Bash|Edit|Write",
  "hooks": [{"type":"command","command":"'$HOME'/.claude/hooks/recovery-class-fragment/recovery-classify.sh","timeout":5000}]
}]' ~/.claude/settings.json > "$TMP" && mv "$TMP" ~/.claude/settings.json
```

## Uninstall

Drop the matcher entry from `~/.claude/settings.json` and `rm -rf ~/.claude/hooks/recovery-class-fragment`. No operator-owned data to purge.

## Performance budget

| Metric | Target |
|---|---|
| Median per-call latency (matched) | ≤ 5 ms |
| Hard timeout | 5000 ms |
| Telemetry write amplification | exactly 1 JSONL line per call with non-empty stderr |

## Forbidden in hook bodies (TM4 / NG6)

`recovery-classify.sh` is shell + jq + python3-fallback + grep only. Enforced by `tests/test-no-claude-spawn.sh`. Charter §2.3 collapses if a runtime hook calls Anthropic.

## References

- Cross-link from governance-pack: [`core/governance-pack/CLAUDE.md`](../governance-pack/CLAUDE.md) §"Recovery-class advisory (opt-in)"
- Precedent shape: [`core/quarantine-pack/`](../quarantine-pack/README.md)
