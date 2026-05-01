# Compatibility Notes: CQR-A Fragment vs Existing CLAUDE.md Rules

## Summary

The `## Model Routing` fragment FOLDS UNDER the three existing rules it touches. It is
the operating-level default for non-Fansipan, non-SDLC-phase work. It does not override
any existing rule; it fills the gap those rules leave open (which model to use when no
explicit phase or path constraint applies).

---

## Rule 1: FANSIPAN ABSOLUTE RULE

**Existing rule**: Any task touching `/home/criznguyen/projects/fansipan/` — including
analysis-only tasks — MUST use Opus. Sonnet and Haiku are FORBIDDEN. No fallback on
"1M context extra-usage required" error.

**How CQR-A interacts**: The fragment explicitly repeats this lock in its
"Hard-locked Opus zones" list:
```
- Anything under `/home/criznguyen/projects/fansipan/` (FANSIPAN ABSOLUTE RULE)
```

This is redundant by design. The FANSIPAN rule in the SDLC block fires first (earlier in
the file). The fragment's restatement ensures that if the model reads the routing section
in isolation, it still sees the lock. There is no conflict — both agree: Fansipan = Opus,
full stop.

**No action required.** Fansipan work is unchanged.

---

## Rule 2: Sub-agent spawn via safe-spawn-claude.sh (CRITICAL 2026-04-21)

**Existing rule**: Every `claude -p ...` spawn MUST go through
`/home/criznguyen/bin/safe-spawn-claude.sh`. The wrapper enforces budget, dedup, and
active-session guards. Calling `claude` directly is FORBIDDEN.

**How CQR-A interacts**: The fragment determines WHICH model to pass to the wrapper.
The call sequence is:

```
1. CQR-A routing rules recommend a model (e.g., claude-sonnet-4-6 for a feature task)
2. Agent drafts the spawn command:
   safe-spawn-claude.sh /tmp/agent.md claude-sonnet-4-6 feature /home/criznguyen/projects/foo
3. safe-spawn-claude.sh runs its guards (budget, dedup, active-session)
4. If guards pass: spawns the claude process with --model claude-sonnet-4-6
```

The fragment and the wrapper are orthogonal layers: fragment = model selection,
wrapper = spawn safety. They do not conflict. The wrapper does NOT override the model
the agent passes — it passes it through verbatim (plus the SAFE_SPAWN_FORCE escape).

**One edge case**: if the wrapper is modified to enforce a `min_model` convention (see
CQR research doc §8.5), it could reject a Haiku recommendation for a class that requires
a minimum of Sonnet. That convention does not currently exist in the wrapper. If added,
the wrapper wins (it is the last gate before process spawn).

---

## Rule 3: SDLC Agent Routing — main orchestrator rule

**Existing rule**: The main agent is an orchestrator, not a worker. All SDLC phases
(PO spec, BA spec, Architecture, Technical BA, Dev implementation, QE test writing,
Security Audit, PE Audit) delegate to Opus sub-agents spawned via CLI in background.
Sonnet/Haiku are not mentioned for these phases — Opus is implicit.

**How CQR-A interacts**: The SDLC routing table specifies WHO does the work (which
agent type, which SDLC phase). It does NOT specify the model for tasks that fall
OUTSIDE an explicit SDLC phase — e.g., ad-hoc file reads, single-function bug fixes,
quick classification tasks, log skims, one-off grep orchestration.

CQR-A covers exactly those gaps. Specifically:

| Work type | Governed by |
|-----------|-------------|
| SDLC PO/BA/Arch/Dev/QE phases | SDLC Agent Routing → Opus always |
| Security Audit / PE Audit | SDLC Agent Routing → Opus (LOCKED) |
| Fansipan (any task) | FANSIPAN ABSOLUTE RULE → Opus (LOCKED) |
| Non-SDLC, non-Fansipan coding tasks | **CQR-A Model Routing** → class-based |
| Ad-hoc read/search/summarize | **CQR-A Model Routing** → Haiku |
| Single-file bug fix | **CQR-A Model Routing** → Sonnet |
| Multi-file feature (2-5 files) | **CQR-A Model Routing** → Sonnet |
| Cross-module refactor / >5 files | **CQR-A Model Routing** → Opus |

**Priority order** (first matching rule wins):

1. FANSIPAN ABSOLUTE RULE (path fence, fires first — highest priority)
2. SDLC Agent Routing phase table (explicit phase → Opus always)
3. CQR-A keyword fence (audit/security/production/... keywords → Opus locked)
4. CQR-A path fence (auth/security/billing/migrations paths → Opus locked)
5. CQR-A session pin (CLAUDE_PIN_MODEL env var → pinned model)
6. CQR-A task-class table (trivial/small/feature/system/audit → mapped model)
7. CQR-A auto-escalation triggers (failure/diff-size/context → upgrade tier)
8. Default: Opus 4.7

Rules 1 and 2 cover the high-cost SDLC work. Rules 3-7 (CQR-A) cover the everyday
noise turns that currently run on Opus unnecessarily. The savings target of 22-30%
comes from routing that noise to Sonnet/Haiku, not from touching SDLC work at all.

---

## What CQR-A does NOT change

- SDLC-phase sub-agents: still Opus, still via safe-spawn-claude.sh.
- Fansipan: still Opus, no exceptions.
- The safe-spawn-claude.sh wrapper requirement: still mandatory for every spawn.
- Background execution requirement: still mandatory for all sub-agents.
- The neural-memory recall-first rule and memory sync rule: unchanged, unrelated.
