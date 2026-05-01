# `audit` — single skill, two severity dimensions

Pre-merge audit sub-agent for `feature` and `system-change` task classes. One skill, two severity dimensions (`security` + `pe`). Folds v0.1 `audit-security` + `audit-pe` per panel §1.4 and `charter-rationale.md` §2.4 (60–70% empirical finding overlap on real diffs).

This README explains: how to invoke, the severity scale, model-selection rules (no Sonnet downshift, ever), wiring to `governance-pack`, integration with `pre-audit-gate.sh` from P0-01, and the build acceptance check against `skills-roadmap-v1.1.md` §2.2.

## Quick start

```bash
# 1. Implementer finishes the feature on a branch.
# 2. Verify is green:
make verify

# 3. Spawn the audit (background; survives SSH disconnect).
#    Symlink opinions/safe-spawn-claude.sh into your PATH (e.g. ~/bin/) and
#    invoke it by basename so this snippet stays portable across operators.
safe-spawn-claude.sh \
  $CLAUDE_PROJECT_DIR/core/audit/prompts/system.md \
  claude-opus-4-7 \
  "audit-${FEATURE_ID}" \
  $CLAUDE_PROJECT_DIR

# 4. Read the report.
```

The auditor writes two files:

| File | Purpose | Schema |
|---|---|---|

## Auto-invocation triggers

The skill's `description:` field auto-attaches when the user prompt contains any of:

- `audit`
- `security review`
- `vulnerability`
- `pre-merge audit`
- `principal engineer review`
- `compliance review`

Use a manual `/audit <id>` form if you want explicit control over the spawn.

## Inputs

| Input | Required | Default | Notes |
|---|---|---|---|
| `<id>` | yes | — | Feature/system-change ID |
| Diff range | no | `git diff main...HEAD` | Override for branch-vs-branch audits |
| `--dim` | no | `security,pe` | Use `security` or `pe` for narrow runs |

If a required input is missing the auditor emits a single MEDIUM `AUDIT-INPUT-GAP` finding, sets verdict BLOCK, and exits. It does NOT synthesise findings without context.

## Severity scale (charter v1.1 §6.1)

| Severity | Meaning | Verdict gate |
|---|---|---|
| CRITICAL | Production data loss, RCE, auth bypass, PII leak | BLOCK; zero-deferral |
| HIGH | Privilege escalation, broken invariant, data corruption window | BLOCK; zero-deferral |
| MEDIUM | Defence-in-depth gap, contract drift, test gap on critical path | Negotiable; document; BLOCK if it contradicts a spec success criterion |
| LOW | Compounding code-smell, missing log, hardcoded value | Track; do not block |
| INFO | Observation, no required action | Informational |

**Zero-deferral on CRITICAL or HIGH.** Charter v1.1 §6 forbids "out of scope," "follow-up later," or "tracked in another ticket" for any CRITICAL or HIGH finding. The auditor cannot soften severity; the human reviewer cannot defer past `commit-and-pr` (P1-11) which refuses to merge while open CRITICAL or HIGH findings exist.

## Model selection — when MAY audit downshift to Sonnet?

**Never. Audit MUST run on Opus.**

Specifically:

- The Fansipan absolute rule (user CLAUDE.md, added 2026-04-26): *"For ANY task touching the Fansipan project — including code, specs, audits, AND analysis-only tasks — sub-agents MUST use Opus. Sonnet and Haiku are FORBIDDEN."*
- The audit-quality requirement (charter v1.1 §2.3 + this skill): an audit that misses a CRITICAL finding is the highest-cost outcome in the SDLC. Opus is the highest-fidelity model. The cost ratio between an Opus audit and a Sonnet audit is small relative to the cost of one missed CRITICAL finding in commercial SaaS.
- Schema enforcement: `schemas/report.json` constrains `auditor_model` to `claude-opus-4-7` or `claude-opus-4-6`. Sonnet/Haiku model IDs will fail schema validation; the wrapper MUST refuse the report.

If you encounter the Anthropic error *"1M context extra-usage required"* while running Opus, surface the error to the user. Do NOT fall back to Sonnet/Haiku. (User CLAUDE.md, Fansipan rule, second paragraph.)

## Wiring to `governance-pack` (P0-03)

`governance-pack` ships `.claude/settings.json` with the permissions and hooks defaults. To activate `audit` cleanly under that template, append the following to the project `.claude/settings.json`:

```jsonc
{
  "permissions": {
    "allow": [
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git show *)",
      "Bash(jq *)"
    ],
    "deny": [
      "Edit",
      "Bash(claude *)",
      "Bash(curl *)",
      "WebFetch"
    ]
  },
  "hooks": {
    "SessionStart": [
      { "matcher": "*",
        "hooks": [{ "type": "command",
          "command": "[ \"$CLAUDE_SKILL\" = \"audit\" ] && cat $CLAUDE_PROJECT_DIR/core/audit/prompts/independence-preamble.md || true" }] }
    ]
  }
}
```

The `Edit` deny + scoped `Write` allowlist enforce the read-only contract. The `Bash(claude *)` deny enforces DO-NOT-DELEGATE (no nested sub-agent spawn from inside the audit). The `SessionStart` hook auto-injects the independence preamble on every spawn so the agent cannot start without reading it.

## Integration with `pre-audit-gate.sh` (P0-01)

`pre-audit-gate.sh` is a **PreToolUse hook**, not a CLI script. It is installed
by `core-config` at `${HOME}/.claude/hooks/pre-audit-gate.sh` and wired in
`settings.json` to fire on every `Task` / `Agent` tool call. It reads the
PreToolUse JSON payload from stdin, decides whether the tool call is an audit
spawn, and exits non-zero (with a BLOCK message on stderr) if the diff still
contains unfinished-work markers.

Hook contract (the actual one):

| Channel | Direction | Format |
|---|---|---|
| stdin | in | PreToolUse JSON (`{tool_name, tool_input, ...}`) |
| stderr | out | human-readable BLOCK reason on refusal |
| exit 0 | — | pass-through (not an audit spawn, or no markers found) |
| exit 2 | — | BLOCK — host MUST refuse the tool call |

What it actually checks (see `core/core-config/hooks/pre-audit-gate.sh`):

1. Is the tool call a `Task` / `Agent` spawn whose `subagent_type`,
   `description`, or `prompt` matches `audit`? If not, exit 0.
2. Resolve scan scope: `git diff <base>...HEAD --name-only`, where base is the
   first reachable of `origin/main`, `main`, `origin/master`, `master`.
   Falls back to tracked files under `src/`, `lib/`, `app/` if no base is
   reachable. Override entirely with `CORE_CONFIG_AUDIT_SCOPE`.
3. Grep each in-scope file for stub markers: `TODO`, `FIXME`, `XXX`,
   `pass # placeholder`, `not implemented`.
4. If any hits → emit a BLOCK message naming first 40 hits and exit 2.
   Otherwise exit 0.

Disable entirely (e.g. for vendored code): `CORE_CONFIG_AUDIT_GATE=0`.

Wiring snippet (already in `core-config/settings.json`):

```jsonc
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Task|Agent",
        "hooks": [{ "type": "command",
          "command": "${HOME}/.claude/hooks/pre-audit-gate.sh" }] }
    ]
  }
}
```

Failure mode the gate catches:

- Auditing an implementation that still has unresolved `TODO` / `FIXME` / `XXX`
  / placeholder / "not implemented" markers in the diff scope → audit would
  flag the markers as findings or rubber-stamp around them. Block instead.

> Note: the hook does **not** verify spec / threat-model / decisions presence
> — that is enforced by the audit sub-agent itself (see §"Inputs" — emits a
> single MEDIUM `AUDIT-INPUT-GAP` finding and BLOCKs).

## Invocation through the main loop


```text
main agent  ─►  /tmp/audit-prompt-<id>.md
                │
                ▼
             safe-spawn-claude.sh ─► claude -p (Opus, isolated worktree)
                                      │
                                      ▼
                                  reads independence-preamble.md
                                  reads system.md
                                  reads security-checklist.md + pe-checklist.md
                                  reads spec / threat-model / decisions / diff
                                      │
                                      ▼
                                  writes <id>-audit-report.md + <id>-findings.json
                                      │
                                      ▼
                                  emits "AUDIT-DONE id=<id> verdict=<v> findings=<n>"
                │
                ▼
main agent reads findings.json, decides next step
```

## Acceptance check (against skills-roadmap-v1.1.md §2.2)

| AC | Status | Evidence |
|---|---|---|
| Spawns via `safe-spawn-claude.sh` (background, dedup, budget) | done | README §"Quick start" + §"Invocation through the main loop" |
| Produces report at named path in <5 min for 500-line diff | runtime | enforced via `report.json::wall_clock_seconds` ≤ 7200; soft target documented |
| Severity scale exactly CRITICAL / HIGH / MEDIUM / LOW / INFO | done | `schemas/finding.json::severity` enum + `prompts/system.md` Step 4 |
| Zero-deferral on CRITICAL / HIGH | done | `prompts/independence-preamble.md` "Forbidden actions"; verdict gate in `prompts/system.md` Step 5 |
| PARANOIA-BUST preamble in spawn prompt | done | `prompts/system.md` first heading |
| DO-NOT-DELEGATE preamble in spawn prompt | done | `prompts/system.md` second heading |
| Auditor does NOT modify code | done | `tools:` allowlist in SKILL.md frontmatter excludes `Edit`/`Write` (except own outputs); also enforced by `governance-pack` deny rules in this README |
| Empty-diff → zero findings | done | `prompts/independence-preamble.md` §"On the empty-diff case" + `prompts/system.md` Step 5 empty-diff branch |
| Planted SQLi → ≥1 CRITICAL or HIGH finding | done | `tests/tasks.yaml` task `audit-sql-injection-diff`; fixture at `tests/fixtures/sqli-fixture.py` |
| Two severity dimensions reported with overlap visible | done | `schemas/finding.json::dimension` enum; `examples/dirty-report.md` shows both dims; SKILL.md "60–70% overlap" framing |

## Tests

A single Promptfoo task ships with the skill at `tests/tasks.yaml`. It mounts `tests/fixtures/sqli-fixture.py` (real Python with a planted SQLi at line 14), spawns the auditor against a synthetic diff that introduces the file, and asserts:

- Output (`<id>-audit-report.md`) contains a finding referencing `sqli-fixture.py:14` (or the relevant line range).
- That finding's severity is CRITICAL or HIGH (regex: `\b(CRITICAL|HIGH)\b`).
- The finding's dimension is `security`.
- The verdict is `BLOCK`.

Run via the repo-root Promptfoo config (P0-06):

```bash
npx promptfoo eval -c promptfooconfig.yaml --tag audit
```

The grader is pinned to `claude-haiku-4-5-20251001` per skills-roadmap-v1.1.md §8.3. Each assertion runs N=3 with ≥2/3 pass per R7 §3.4.

## Frequently asked

**Why one skill not two?**
Panel §1.4 + `charter-rationale.md` §2.4: empirical finding overlap on real diffs is 60–70%. Two parallel auditors voting on overlapping findings makes severity laundering worse, not better. Maintenance burden of two prompts is doubled forever. The decision is reversible: split if 8+ weeks of dogfood show divergence.

**Why does `audit` need the threat-model and `decisions.md`?**
Without project context the auditor degrades into paranoid hallucination — flagging everything HIGH because nothing is known to be acceptable. The threat-model names which adversaries and assets are in scope; `decisions.md` lists which alternatives were considered and rejected. Both are required guards. [E1 F6]

**Why isolated worktree?**
Independence-of-reviewer (charter v1.1 §2.3): the auditor must not have written the code. The Anthropic best-practices doc names the writer/reviewer split as the highest-leverage anti-bias technique. Isolation enforces it deterministically; we do not rely on the auditor "trying" not to anchor on prior context.

**Why not run audit on every commit?**
Cost (Opus). Slowness (5 min wall-clock for 500-line diff). And it dilutes the gate: every commit being audited means no commit being audited carefully. Use `delta-code-review` (P0-05, Sonnet, fast) on every commit; reserve `audit` for phase-8/9 gates.

**Can I run only `--dim security` for hot-fixes?**
Yes — for a hotfix that changes one line and has no PE surface, `--dim security` is appropriate and faster. The default is `security,pe` because most diffs are non-trivial enough to merit both.

## Files in this skill

| Path | Purpose |
|---|---|
| `SKILL.md` | Frontmatter + skill body (Anthropic / Superpowers spec) |
| `prompts/independence-preamble.md` | "You did NOT write this code" reminder; loaded first |
| `prompts/system.md` | System prompt with PARANOIA-BUST + DO-NOT-DELEGATE preambles + procedure |
| `prompts/security-checklist.md` | Security-dimension checklist (sections A–M) |
| `prompts/pe-checklist.md` | PE-dimension checklist (sections P–X) |
| `schemas/finding.json` | JSON Schema for one finding |
| `schemas/report.json` | JSON Schema for the report (validates the findings array via `$ref`) |
| `examples/clean-report.md` | Reference PASS report |
| `examples/dirty-report.md` | Reference BLOCK report (2 CRITICAL + 3 MEDIUM + 1 LOW) |
| `tests/tasks.yaml` | Promptfoo task: SQLi-fixture audit must catch ≥ HIGH |
| `tests/fixtures/sqli-fixture.py` | Planted-bug Python fixture (real SQLi) |
| `README.md` | This file |

## Install

See `core/audit/SKILL.md` `## Install`. Short version: `git pull`. The
`ai_disclaimer:` frontmatter literal is read at audit spawn from your
working tree; no `governance-pack/install.sh --refresh-prompts` flag is
required because the spawn-time read IS the install path.

### Glossary (v1.2+)

```bash
git pull
bash core/governance-pack/install.sh --refresh-prompts
```

The `--refresh-prompts` flag re-syncs `core/audit/prompts/*` into the install
destination idempotently (clobber-on-copy; canonical source is
`$CLAUDE_HOME/skills/audit/prompts/`). Running it twice produces the same
state.

### Local vs CI glossary sourcing

The auditor reads `core/audit/prompts/glossary.md` from one of two paths:

| Mode | Path | Integrity |
|---|---|---|
| CI (audit-required.yml) | `$AUDIT_GLOSSARY_PATH` (temp file materialised via `git show ${{ github.event.pull_request.base.sha }}:core/audit/prompts/glossary.md`) | Base-SHA-pinned; charter §2.3 independence at the prompt-content layer |
| Local `/audit` | `$CLAUDE_PROJECT_DIR/core/audit/prompts/glossary.md` (working-tree HEAD) | Advisory; operator's own tree is trusted |

The asymmetry is intentional: CI cannot trust the head copy because a
malicious PR could neuter the vocabulary mid-audit; local development must
be allowed to iterate on the glossary in the same session. The AUDIT-002
classifier-sourcing precedent in `audit-required.yml` is the same primitive
applied to a different prompt fragment. Missing-on-base or missing-locally
is non-fatal; the auditor falls back to prose vocabulary already carried by
`system.md`, `security-checklist.md`, and `pe-checklist.md`.

## Uninstall

The 3-line revert path for the v1.2+ glossary file (per spec §G6 / AC6):

1. Delete `core/audit/prompts/glossary.md`.
2. Revert the `Source audit glossary from BASE SHA` step in
   `.github/workflows/audit-required.yml`.
   (`audit-glossary-banned-phrase-guard`, `glossary-stale-warn`,
   `glossary-consistency-check`, `audit-glossary-ab-gate`) plus the
   `tests/tools/audit-glossary-ab-summarize.sh` helper in

After these reverts, `core/audit/prompts/system.md` Step 1 falls back to
the prose vocabulary in `security-checklist.md` and `pe-checklist.md`;
baseline ASR ≥85% is maintained on `core/audit/tests/tasks.yaml`.

## Authoring rule for decisions.md

Do NOT paste the `ai_disclaimer:` literal from `core/audit/SKILL.md`
and the `disclaimer-absence-guard` job in

## Citation backbone

