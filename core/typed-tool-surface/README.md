# `typed-tool-surface` — convention + PreToolUse JSON-Schema validator

v2.0 Top-5 #4. Charter §2.2 mechanism upgrade.

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body. |
| `CLAUDE.md` | Skill-author guidance for writing JSON Schema for tool args. |
| `hooks/schema-validate.sh` | PreToolUse(`*`). jq-based schema validation. |
| `templates/schema-template.json` | Schema skeleton. |
| `templates/blast-radius-table.md` | 5-tier taxonomy. |
| `tests/test-schema-validate.sh` | pass/fail/skip cases. |
| `tests/test-blast-radius-lookup.sh` | precedence + opt-out cases. |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |
| `examples/sample-skill-frontmatter.md` | Reference SKILL.md frontmatter. |

## Migration — 22 v1.1.6 FULL-coverage skills

Per research §4 Top-5 #4 F2-5, the bulk-convert of existing FULL-coverage skills is **deferred to a follow-up PR**. The validator ships in v2.0 with:

- Default behavior: skills missing `blast_radius:` get `decision=skip` and an advisory line; the hook does NOT refuse.
- Promotion behavior: after the bulk-convert lands, the operator flips a one-line config (`~/.claude/typed-tool-surface.json` `mode: strict`) and missing frontmatter becomes `decision=fail` instead.

### v1.1.6 FULL-coverage skills target table

| Skill | Target `blast_radius:` |
|---|---|
| `core/audit/SKILL.md` | `read-only` |
| `core/governance-pack/templates/postconditions.d/_self.sh` | `local-write` (writes audit logs) |
| `core/quarantine-pack/SKILL.md` | `read-only` |
| `core/recovery-class-fragment/SKILL.md` | `read-only` |
| `core/git-force-push-gate/SKILL.md` | `external-side-effect` |
| `core/hardcoded-credential-refusal/SKILL.md` | `local-write` |
| `core/file-write-stale-stat-refusal/SKILL.md` | `local-write` |
| `core/eval-contamination-probe/SKILL.md` | `read-only` |
| `core/loop-circuit-breaker/SKILL.md` | `local-write` |
| `core/typed-tool-surface/SKILL.md` | `read-only` |
| `core/sandbox-default-on/SKILL.md` | `read-only` |
| `core/core-config/SKILL.md` | `local-write` |
| `core/delta-code-review/SKILL.md` | `read-only` |
| `core/worktree-spawn/SKILL.md` | `local-write` |
| `opinions/safe-spawn-claude/SKILL.md` | `external-side-effect` |
| `opinions/lessons/SKILL.md` | `local-write` |
| `opinions/model-routing/SKILL.md` | `read-only` |
| `opinions/coverage-discipline/SKILL.md` | `read-only` |
| `opinions/anti-pattern-governance-template/SKILL.md` | `read-only` |
| `opinions/cqr-flag-template/SKILL.md` | `read-only` |
| `opinions/spec-hash-traceability/SKILL.md` | `read-only` |
| `opinions/audit-builtin/SKILL.md` | `local-write` |

The bulk-convert PR adds the line to each frontmatter; this PR ships the validator that *will* enforce them.

## Install

```bash
bash core/governance-pack/install.sh   # Step 16
```

The installer:
1. Copies `hooks/schema-validate.sh` to `~/.claude/hooks/typed-tool-surface/`.
2. Seeds `~/.claude/typed-tool-surface.json` (default `mode: advisory`).
3. Registers `PreToolUse(.*)` matcher in settings.

## Uninstall

```bash
bash core/governance-pack/uninstall.sh
rm -rf ~/.claude/typed-tool-surface ~/.claude/typed-tool-surface.json
```

## Performance budget

| Path | Target | Cycle-1 measurement |
|---|---|---|
| With-schema-loaded p50 | ≤ 30 ms | **~34 ms** (was ~129 ms pre-Cycle-1; 3.7× speedup) |
| No-schema fast-skip p50 | ≤ 30 ms | **~34 ms** (was ~39 ms) |

Cycle-1 remediation (Finding-S8-1) consolidated 4 separate `python3 -c`
invocations into a single one (stdin parse + schema-cache lookup + JSON-Schema
validation in one Python startup). The residual ~34 ms is dominated by Python
import cost and is acceptable to NOT meet the charter §2.2 prose target of
≤ 5 ms (`jq-check`) at this layer — the charter target is reachable only with
a persistent jq path, which research §5 P1 #4 deferred to v2.1. The threat-
residual.

Bench harness:

```bash
TMP=$(mktemp -d); HOME=$TMP; export HOME
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x","old_string":"a","new_string":"b"},"session_id":"audit-bench"}'
T0=$(date +%s%3N)
for i in $(seq 1 50); do
  printf '%s' "$PAYLOAD" | bash core/typed-tool-surface/hooks/schema-validate.sh >/dev/null 2>&1 || true
done
T1=$(date +%s%3N)
echo "per-call ~$(( (T1 - T0) / 50 ))ms"
rm -rf "$TMP"
```

## References

