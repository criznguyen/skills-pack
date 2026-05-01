# claude-skills Charter v1.1 — SDLC Playbook for AI Coding Agents

**Status:** v1.1 — post-panel rewrite, replaces v0.1 in full
**Date:** 2026-04-28
**Replaces:** [`docs/synthesis/charter.md`](../charter.md) (v0.1, REWORK by 5-expert panel)
**Companion docs:** [`charter-rationale.md`](./charter-rationale.md) — every decision and trade-off; `skills-roadmap-v1.1.md` (separate sub-agent) — the build list this charter motivates
**Citation convention:** `[Source: <path-or-url>]` inline for every load-bearing claim; `[panel:E<n> <ID>]` for expert findings.

## 1. Mission and scope

The charter requires every Claude Code session in this user's projects to produce modern, high-quality software at the right scale of ceremony. The library defends against five recurring failure modes documented across the research corpus and the Fansipan production history [Source: docs/research/02-sdlc-methodology.md §3.3; docs/research/03-prompt-engineering.md §7]:

- **Sidetrack** — agent solves the wrong problem because discovery was skipped.
- **Scope creep** — refactors leak into bug-fixes; "nice-to-haves" creep into MVPs.
- **Fantasy approval** — agent reports "done" while stubs, TODOs, or skipped tests remain.
- **Context loss** — multi-day work loses memory between sessions and across `/clear`.
- **Skipped review** — code lands without independent audit.

The output is a composable kit of Claude-native primitives — skills, sub-agents, slash commands, hooks, settings bundles, and CLAUDE.md snippets — that drop into vanilla `~/.claude/` and `.claude/` [Source: docs/research/05-authoring-format.md §2]. The charter does not build another framework; it encodes a disciplined senior engineer's habits as `SKILL.md` files and ships them alongside deterministic enforcement hooks.

**Audience and selection bias.** The evidence base is Anglophone-dominant and AI-native-company-dominant [panel:E4 §4.3]. Vietnamese and Chinese practitioner sources surface two patterns the Anglo corpus omits: multi-model cost-routing and enterprise IM bridges (Feishu/DingTalk/WeCom) [Source: docs/research/06-ecosystem-and-superpowers.md §5]. The charter targets **solo dev workflows with team-mode as future work** and acknowledges that some defaults (safe-spawn config, model selection tuning) are operator-specific — see §5 for the partition.

**What this charter is not.** It is not a methodology manifesto, not a Spec-Kit competitor, not a framework. It is the load-bearing decision document the project's main agent and every shipped skill consults when in doubt.

## 2. Five load-bearing principles

Each principle gets one paragraph, ≥2 citations, and ≥1 enforcement mechanism. The principles are ordered by load-bearing weight (anti-fantasy first because hallucination is the cheapest-to-prevent and highest-frequency failure mode).

### 2.1 Anti-fantasy

The charter requires every session to refuse fantasy claims about files, APIs, libraries, flags, and prior decisions. Anthropic's own reduce-hallucinations guide names *"allow Claude to say I don't know"* and *"verify before claiming"* as the #1 hallucination reducers [Source: https://platform.claude.com/docs/en/build-with-claude/reduce-hallucinations]. Cursor's leaked system prompt confirms convergent design: *"if a file/function/symbol is referenced and you have not read it, read it first"* [Source: docs/research/03-prompt-engineering.md §4.1]. The user's documented incident `feedback_silent_fail_token_burn` (2026-04-21) and the broader DAPLab "70% complete then it falls apart" pattern both root-cause to silent hallucination on truncated reads [Source: https://daplab.cs.columbia.edu/general/2026/01/07/why-vibe-coding-fails-and-how-to-fix-it.html, panel:E2 §4 trace]. The Read-tool default of 2,000 lines per call is documented in the Claude Code Read-tool description; behavior beyond 2,000 lines is truncation, and community reports (HN GSD thread item 44837518) correlate truncated reads with patches against imagined file content [Source: https://news.ycombinator.com/item?id=44837518; docs/review/v1.1/CITATIONS-FIXED.md §2]. The v0.1 citation that attributed specific numerical caps ("200-line memory cap with silent truncation," "2,000-line read ceiling beyond which the agent hallucinates") to `alex000kim`'s source-leak post is **withdrawn** — those quotes are not in the cited source [panel:E2 C1; docs/review/v1.1/CITATIONS-FIXED.md §2].

**Enforcement mechanism.** A `PostToolUse` hook (`core/governance-pack/hooks/postcondition-hook.sh`) verifies the world matches the claim after each state-changing tool call. Verification logic lives in operator-owned `~/.claude/postconditions.d/*.sh` (flat command-pattern table — F2-1); 9 defaults ship for mkdir, git push, Edit, Write, mv, rm, bash, npm install, pytest. Default-on for `feature` / `system-change` task classes; opt-in for `trivial` / `small` via SKILL.md frontmatter `postcondition_required: true` (F4-8). Ships shadow-mode (advisory stderr + JSONL) for 30 days before operator-driven promote to `exit 2` blocking (F2-7). The prior CLAUDE.md `anti-fantasy-rules` snippet is RETIRED in favor of this hook; the snippet's read-before-patch and no-symbol-without-grep prose are absorbed into `core/governance-pack/CLAUDE.md` advisory copy. Cites the four `b3-failures.md` P0-C incidents (I-1 Replit, I-2 PocketOS, I-3 Gemini CLI, I-10 Devin) and Anthropic's reduce-hallucinations guide §"verify before claiming". See [`docs/sdlc/spec/postcondition-hook.md`](../../sdlc/spec/postcondition-hook.md).

### 2.2 Hooks > rules for high-blast-radius operations

Deterministic enforcement beats prose enforcement. Anthropic states: *"Hooks are deterministic and guarantee the action happens"* [Source: https://code.claude.com/docs/en/hooks-guide]. The Replit `DROP TABLE` incident (July 2025, prod database wiped during a code freeze) and the Cursor PocketOS deletion (April 2026, Railway volume deleted in 9 seconds with an over-permissioned token) both happened because the rule was a system-prompt instruction, not a `PreToolUse` hook with `exit 2` block semantics [Source: https://fortune.com/2025/07/23/ai-coding-tool-replit-wiped-database; https://www.theregister.com/2026/04/27/cursoropus_agent_snuffs_out_pocketos/]. Anthropic now ships 13 hook lifecycle events — UserPromptSubmit, PreToolUse, PostToolUse, Notification, Stop, SubagentStop, SubagentStart, PreCompact, SessionStart, SessionEnd, PermissionRequest, PostToolUseFailure, Setup [Source: https://github.com/disler/claude-code-hooks-mastery; docs/review/v1.1/CITATIONS-FIXED.md §4]. The earlier "8 events" framing inherited from the now-replaced `iamrajiv/claude-code-hook-templates` (0★, 1 commit, unpopulated) is corrected here [panel:E4 audit row 9; docs/review/v1.1/CITATIONS-FIXED.md §4].

**Enforcement mechanism.** A `safety-hooks-bundle` (PreToolUse `block-destructive-bash`, PreToolUse `freeze-list`, PostToolUse `auto-lint-on-write`) ships in P0. Reference implementations: `disler/claude-code-hooks-mastery` (3.6k★) and Anthropic's own `ralph-loop` plugin in `claude-plugins-official` for the continue-until-X pattern [Source: https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-loop].

**§2.2 sub-clause #2 — Tool-result quarantine.** Externally-sourced content (MCP user-content surfaces, `WebFetch`, `Read` of `**/uploads/**`) is advisory-tagged at the boundary. A `PostToolUse` hook (`core/quarantine-pack/hooks/wrap-mcp-output.sh`) appends `[QUARANTINE-NOTICE: ...]` to the next-turn context via `hookSpecificOutput.additionalContext`. Trusted MCPs (`linear`, `github`, `jira`, …) opt out via `templates/trusted-mcp-allowlist.txt`. Structural quarantine — wrapping `tool_response` before context ingestion — is deferred to v2.1 contingent on Anthropic shipping a `PreToolResultCommit` hook (see §2.4-bis tracker). The `<UNTRUSTED>` prompt-pattern lives in `core/quarantine-pack/README.md` as developer onboarding only; adversarial close-tag spoofing defeats it as a structural defense, so the charter does not promise it as one. See [`docs/sdlc/spec/quarantine-pack.md`](../../sdlc/spec/quarantine-pack.md).

**§2.2 sub-clause #1 — Every autonomous loop declares a halt condition the harness can check deterministically.** `core/loop-circuit-breaker/` ships per-session counters (iteration count, USD cost, tool-call hash collisions); `opinions/safe-spawn-claude/` retains per-spawn defaults (50MB / 10min / 2min). USD ceiling fires *between* tool calls (PostToolUse + Stop), not before. Bypass via orchestrator-issued env-var token (`LOOP_BREAKER_BYPASS_TOKEN`) is background-safe — orchestrator drains halt-event from sub-agent stdout/JSONL and decides bypass-and-resume or kill. No silent sub-agent deaths from gate-fire (F12 fix). See [`core/loop-circuit-breaker/`](../../../core/loop-circuit-breaker/README.md) and [`docs/conventions/loop-circuit-breaker-bypass.md`](../../conventions/loop-circuit-breaker-bypass.md).

**Mechanism upgrade — typed tool surface.** Hooks read typed `blast_radius` ∈ {read-only, local-write, repo-write, network-write, external-side-effect} and JSON Schema for tool args, not prose patterns. Each SKILL.md declares both via frontmatter `blast_radius:` and `args_schema:`. `core/typed-tool-surface/hooks/schema-validate.sh` (PreToolUse) validates `tool_input` pre-dispatch; latency target <5ms (jq-check). Schema-drift detection via per-skill `last-validated:` discipline + CI checks. Foreclosure-must-ship in v2.0 — retrofit cost is prohibitive in v2.1+. See [`core/typed-tool-surface/`](../../../core/typed-tool-surface/README.md).

**Default-deny sandbox** via `governance-pack/install.sh --enable-sandbox` is the default-on enforcement of blast-radius typing (Anthropic vendor 2025-10-19). Per-skill opt-out via SKILL.md frontmatter `sandbox_required: false`. Documented rollback recipe at `core/sandbox-default-on/templates/sandbox-rollback.md`. See [`core/sandbox-default-on/`](../../../core/sandbox-default-on/README.md).

### 2.3 Independence-of-reviewer

Audits run in a fresh sub-agent context with the diff and spec only — never with the implementation transcript [Source: docs/research/02-sdlc-methodology.md §6.4]. Anthropic recommends the writer/reviewer split: *"a fresh context improves code review since Claude won't be biased toward code it just wrote"* [Source: docs/research/03-prompt-engineering.md §3.4]. Fansipan's 130-finding closure run validated this empirically [Source: user CLAUDE.md SDLC routing rules; project_fansipan_wave_c_complete memory]. The pattern resists three predictable degradations: rubber-stamping (auditor returns "no issues" on a sloppy diff), paranoid hallucination (auditor flags everything HIGH because it has no project context), and severity laundering (CRITICAL findings reframed as "out of scope") [panel:E1 F5; panel:E3 §3.4]. The audit prompt MUST include the threat-model output from Phase 4 plus a `decisions.md` rejected-alternatives log so the auditor has tacit context the diff alone cannot carry [panel:E1 F6].

**Enforcement mechanism.** A single `audit` sub-agent ships in P0 with two severity dimensions (`security` and `pe`) instead of two separate sub-agents [panel:E2 C2; panel:E3 §2 row 18]. Spawned via `safe-spawn-claude.sh` (background, dedup, budget-guarded); `tools: Read, Grep, Glob` only; severity scale CRITICAL/HIGH/MEDIUM/LOW/INFO; "do NOT modify code" flag enforced; output to `docs/sdlc/audit/<id>-report.md`. Split into two sub-agents only after 8+ weeks of dogfood shows non-trivial divergence in findings.

### 2.4 Compose primitives, don't reinvent

CLAUDE.md = facts. Skills = procedures. Sub-agents = isolated work. Hooks = deterministic enforcement. MCP = external systems [Source: docs/research/01-anthropic-official.md §2.8; docs/research/05-authoring-format.md §2]. Picking the wrong primitive is the most common authoring error [panel:E1 strongest finding #6; panel:E2 §5 #3]. The 2026 community has converged on three frameworks the v0.1 charter failed to acknowledge — naming them is non-negotiable [panel:E4 §1 verdict; docs/research/06-ecosystem-and-superpowers.md §1].

**`obra/superpowers` (Jesse Vincent, Prime Radiant) — 169,961★ on 2026-04-28, MIT, accepted into `anthropics/claude-plugins-official` on 2026-01-15** [Source: https://github.com/obra/superpowers; docs/research/06-ecosystem-and-superpowers.md §2.1]. Ships a 7-phase workflow: Brainstorming → Git Worktrees → Writing Plans → Subagent-Driven Development → Test-Driven Development → Requesting Code Review → Finishing a Development Branch [Source: https://github.com/obra/superpowers/blob/main/README.md]. Skills are "documented procedures the agent must consult before acting." Distributed cross-tool to Claude Code, Cursor, OpenCode, GitHub Copilot CLI, and Gemini CLI — the format is portable. **claude-skills complements Superpowers; it does not compete with or wrap it.** Superpowers handles the 7-phase build loop; claude-skills layers governance gates (audit, security review, PE review, freeze hooks, spec-hash traceability) that Superpowers does not ship. v1.1 will ship `compat/superpowers.md` mapping each Superpowers phase to the claude-skills primitive that hardens it [docs/review/v1.1/CITATIONS-FIXED.md §3].

**`thedotmack/claude-mem` — 68,583★, AGPL-3.0, MCP+SQLite+Chroma persistent memory plugin** [Source: https://github.com/thedotmack/claude-mem; docs/research/06-ecosystem-and-superpowers.md §3]. Provides episodic cross-session recall via 5 lifecycle hooks, SQLite+FTS5, Chroma vector DB, and a `mem-search` skill with progressive disclosure. **claude-skills declares interop, not duplication**: episodic + observational memory belongs in claude-mem; procedural + governance memory (skill files, audit gates) stays in claude-skills. AGPL-3.0 contamination is avoided by staying on the MCP/plugin boundary — never forking claude-mem internals [docs/research/06-ecosystem-and-superpowers.md §3.2].

**`garrytan/gstack` — 85,291★, MIT, role-bound skills mapped to a virtual eng team** [Source: https://github.com/garrytan/gstack; docs/research/06-ecosystem-and-superpowers.md §4]. 23 commands across 6 roles (CEO, Designer, Eng Manager, Staff Engineer, QA, Release Manager) plus guardrail commands (`/careful`, `/freeze`, `/guard`, `/unfreeze`). claude-skills lifts gstack's role-bound naming convention (skills encode *who-runs-this-when*) and the guardrail command idiom into the §4 phase model.

**VN/CN community patterns.** Vietnamese and Chinese practitioners standardize on multi-model cost-routing (`musistudio/claude-code-router` 33.1k★, `Wei-Shaw/claude-relay-service` 11.4k★) and enterprise IM bridges (`cc-connect` for Feishu/DingTalk/WeCom, `@larksuiteoapi/lark-mcp`) [Source: docs/research/06-ecosystem-and-superpowers.md §5; https://github.com/musistudio/claude-code-router]. Roadmap §6's prior hard out-of-scope on multi-model orchestration is softened to phase-2 deferral with a stub example today.

**Enforcement mechanism.** Every primitive shipped under the roadmap declares its `Type` in one of seven canonical buckets. The README ships the R5 §2 decision matrix verbatim — *"I want to add behavior X. Which primitive?"* [Source: docs/research/05-authoring-format.md §2]. The charter explicitly forbids inventing a primitive that already exists in vanilla Claude Code (`/review`, `Explore` agent, `notify`, `--continue`, `claude --resume`).

**MCP boundary (cross-ref).** MCP tool-results from user-content surfaces flow through advisory wrap (charter §2.2 sub-clause #2); see [`core/quarantine-pack/`](../../../core/quarantine-pack/README.md).

### 2.4-bis Vendor-risk register

The charter builds on Anthropic primitives that are still maturing. **The risk is real and named here, not hidden behind PLAN.md non-goal #2.** Concrete dependencies and worst-case scenarios:

- `context: fork` (sub-agent forking) is **experimental** and gated behind `CLAUDE_CODE_FORK_SUBAGENT=1` in v2.1.117+ [Source: docs/research/05-authoring-format.md §11; panel:E2 M3]. Worst case if Anthropic deprecates fork: P0 entries that depend on isolated-context investigation lose their isolation primitive and must fall back to message-passing supervisor chains (which collapse at 8–12 hops per docs/research/02-sdlc-methodology.md §4.2).
- Hook event surface has changed: `Task` tool was renamed to `Agent` (v2.1.63), `/pr-comments` was removed (v2.1.91), `/vim` was removed, custom commands merged into skills [Source: docs/research/05-authoring-format.md §11]. Average velocity: ~1 breaking format change per 6 weeks. Skills and hooks have a ~6-month TTL before something they depend on becomes deprecated or renamed [panel:E3 §5].
- Sub-agent isolation semantics are vendor-specified; the charter assumes `tools` allowlist and `disable-model-invocation: true` continue to be honored. Worst case: if `disable-model-invocation` becomes opt-out, the `commit-and-pr` skill (P0) loses its manual-only gate and must move to a hook.
- Plugin sub-agents cannot ship hooks/MCP/`permissionMode` for security reasons [Source: docs/research/05-authoring-format.md §10]. claude-skills cannot package P0 audit primitives as plugin sub-agents; they ship as standalone files with install instructions.
- The Boris Cherny "259 PRs in 30 days" workflow is **vendor-internal** — the author works at Anthropic, with internal API quotas, 1M-context Sonnet/Opus access, and dogfooding tooling that does not generalize [panel:E3 §6; panel:E4 §4.2; docs/review/v1.1/CITATIONS-FIXED.md §5].

**Mitigation.** Every skill ships with a `last-validated:` frontmatter date [panel:E3 §5]. Quarterly review (§9 in `charter-rationale.md`) flags any skill not validated in 90 days. Format churn is real; the charter does not pretend otherwise.

**Vendor ASKS (the upstream surface this charter wants Anthropic to ship).** Each entry is an outstanding ask whose absence forces the corresponding charter primitive into a degraded shape; quarterly review re-checks vendor adoption.

- (g) `PreToolResultCommit` hook to enable structural tool-result quarantine (current advisory mode is non-structural; see `core/quarantine-pack/` v2.0 ship).
- (h) Skill-schema runtime adoption — if Anthropic adopts our JSON Schema convention as runtime validation, `core/typed-tool-surface/hooks/schema-validate.sh` PreToolUse becomes redundant (graceful degradation).
- (i) Sandbox runtime continuation — `core/sandbox-default-on/` installer becomes vestigial if Anthropic deprecates the sandbox primitive. Quarterly review per §8.

### 2.5 Verifiability is the highest-leverage input

*"Include tests, screenshots, or expected outputs so Claude can check itself. This is the single highest-leverage thing you can do"* [Source: https://code.claude.com/docs/en/best-practices]. The Columbia DAPLab study found a recurring "70% complete then it falls apart" pattern, root-caused to silent error handling and business-logic divergence — both prevented by attaching an executable verification command to every task [Source: https://daplab.cs.columbia.edu/general/2026/01/07/why-vibe-coding-fails-and-how-to-fix-it.html]. ATDD takes this further: the user-readable Given/When/Then test is written first, by a different agent than the implementer [Source: docs/research/02-sdlc-methodology.md §3.3]. Hamel Husain's evals discipline is the operational corollary: *"Binary pass/fail with detailed critiques (not 1-5 scales)"*; every P0 skill MUST ship with a `tests/` folder containing 3–5 golden tasks [Source: https://hamel.dev/blog/posts/field-guide/; docs/research/07-evals-and-learning-loops.md §1].

**Enforcement mechanism.** Every `SKILL.md` template ships with a mandatory `# Verification` section. The library itself ships a `tests/` skeleton in P0 (see §7). Block merge of any new skill PR that does not include the test folder [Source: docs/research/07-evals-and-learning-loops.md §8.2]. Eugene Yan: *"Building solid evals should be the starting point for any LLM-based system or product"* [Source: https://eugeneyan.com/writing/llm-patterns/].

## 3. Task-class rubric (CLAUDE.md, 8 lines)

The charter REPLACES the v0.1 `task-class-router` skill with the rubric below [panel:E3 §3.1; PANEL-INTEGRATION.md §2.5]. Auto-routing creates friction that users override; classification is the user's job. The rubric reads in 30 seconds and ships in `~/.claude/CLAUDE.md`:

```markdown
## Task class — pick one before starting (read the rubric):
- trivial: <5 LoC, no behavior change, no public-API change → skip plan, just do it
- small: 1-3 files, 1 module, no contract change → Plan Mode, then implement
- feature: multi-file or new behavior, optional contract change → spec → plan → implement → audit
- system-change: production-touching, contract-breaking, or security-critical → full pipeline (phases 4-10c)

Upgrade triggers: discovered new contract change, discovered security-critical path, blast radius beyond initial estimate.
Downgrade triggers: discovery showed the "feature" was a config tweak, no behavior change after spec'ing.
```

**Why this is a rubric, not a skill** [panel:E1 F3; panel:E3 §3.1; panel:E5 §4.2]: blast radius and reversibility are stronger predictors of risk than file count. A single-line change to `auth/session.go` is system-change-class; a 200-line change to a CLI help text is small-class. A skill that auto-classifies will misclassify on this dimension constantly. The rubric also has an explicit downgrade path (the upgrade-only v0.1 router did not). The user reads 8 lines and decides.

## 4. Phase model

The 10 phases below are the **upper bound rubric**, not a mandatory minimum and not separate skills [panel:E2 M1; PANEL-INTEGRATION.md §2.1]. The task-class rubric in §3 decides which slice runs. The v0.1 phase-as-skill primitives (`phase-gate`, `tasks-decompose`, `architect-adr`, `tech-spec-contract`, `po-stories`, `ba-edge-cases`) are KILLED [panel:E2 rec #5; panel:E3 §2; PANEL-INTEGRATION.md §1.3]; the discipline survives as artifact convention only.

| # | Phase | Output | Gate class | Failure if skipped |
|---|---|---|---|---|
| 1 | Discovery / Intake | Problem statement, non-goals | `[human-ack]` | Solving the wrong problem |
| 2 | PO / Requirements | User stories with G/W/T ACs | `[llm-judge]` | Scope creep |
| 3 | Business Analysis | Domain model, edge cases, glossary | `[human-ack]` | Hidden invariants violated |
| 4 | Architecture + threat model | ADRs, integration contracts, **5-line "what could go wrong"** | `[llm-judge]` | Integration blockers, missed threats |
| 5 | Technical BA / Spec | Typed contracts, test plan with examples | `[machine]` (compiles/lints) | Coding agent fills gaps |
| 6 | Implementation | Code + unit tests, scoped commits, **`decisions.md`** | `[machine]` (lint+typecheck+tests green) | Wrong problem, over-engineering |
| 7 | QE / Testing | Coverage, integration tests against real deps | `[machine]` if dep harness exists | Mock-vs-real divergence |
| 8 | Audit (security + PE, single sub-agent, two severity dimensions) | Findings CRITICAL/HIGH/MEDIUM/LOW/INFO | `[machine]` (audit-findings-file-exists + verdict=PASS, gated on task class ∈ {feature, system-change}) | Insecure code shipped |
| 10a/b | Release engineering + Operability handover | Rollout plan, observability, alert thresholds | `[machine]` (rollback path tested) | Silent regression |
| 10c | **Post-launch validation** (system-change ONLY) | Telemetry confirms intent within N days OR exception filed | `[machine]` | Built, never used, nobody noticed |

**Honest gate labels** [panel:E1 F4]. Four of ten gates are genuine machine checks (`[machine]`); four are LLM-judge gates wearing a gate costume; two are human-ack gates. The v0.1 framing of "machine-checkable artifacts as gates" is overstated and the table above corrects it. (Phase 8 was upgraded from `[llm-judge]` to `[machine]` in v1.1 via the `audit-builtin` feature — the LLM still produces the verdict, but a CI workflow checks the artifact's existence and `verdict=PASS` deterministically. See [`docs/sdlc/spec/audit-builtin.md`](../../sdlc/spec/audit-builtin.md).)

**Phase 4 threat-modeling is mandatory** [panel:E1 F2; PANEL-INTEGRATION.md §2.2]. A 5-line "what could go wrong" section in the architecture spec is the cheapest place to find security bugs. Even partial signal catches the egregious stuff (hardcoded secrets, missing authn entirely). The Phase 8 audit verifies earlier signals, not first-look.

**`decisions.md` is mandatory in Phase 6** [panel:E1 F6]. Per task: list rejected alternatives and why. The Phase 8 audit reads `spec.md` + diff + `decisions.md`, not just spec + diff. Filesystem handoff is lossy compression; the decisions log restores the rationale the diff alone cannot carry.

**Phase 10c (post-launch validation) applies only to `system-change`** [panel:E1 F1; PANEL-INTEGRATION.md §2.1]. Other classes ship without telemetry-confirmation gates because the cost of the gate exceeds the cost of the failure mode for those classes.

**Backtrack protocol** [panel:E1 F9]. Phase artifacts get version stamps; backtrack invalidates downstream artifacts; the implementer logs the backtrack reason in `decisions.md`. The phase model is not forward-only.

## 5. Library partition: `core/` vs `opinions/`

The library claim of "community-portable" (PLAN.md non-goal #2) is incompatible with this user's machine-tuned defaults [panel:E1 F10; PANEL-INTEGRATION.md §2.4]. The charter partitions the library into two folders. Universal rules go in `core/`; operator-specific defaults go in `opinions/`. Other users opt in.

| Rule / primitive | core/ | opinions/ | Why |
|---|---|---|---|
| Anti-fantasy CLAUDE.md snippet | YES | — | Universal hallucination guard [panel:E1 #5] |
| Hooks > rules principle | YES | — | Vendor-agnostic guidance |
| Independence-of-reviewer pattern | YES | — | Empirically validated [panel:E1 #2] |
| Compose-don't-reinvent decision matrix | YES | — | Universal authoring discipline |
| `safety-hooks-bundle` (block-destructive, freeze-list, auto-lint) | YES | — | Universal blast-radius defense |
| `governance-pack` (settings template) | YES | — | Generic defaults |
| `audit` sub-agent template | YES | — | Pattern is generic |
| `task-class` rubric (the 8 lines) | YES | — | Generic |
| Phase-model artifact conventions (`docs/sdlc/<phase>/`) | YES | — | Generic |
| `safe-spawn-claude.sh` 50MB/day budget | — | YES | Tuned for this user's quota and incident history |
| 120s active-session window | — | YES | Tuned to this user's workflow |
| Dedup heuristic (10-min hash window) | — | YES | Tuned default |
| MEMORY.md schema (auto-memory + neural-memory + lessons.md layering) | — | YES | This user's specific layered system |
| Model-selection rule (Opus for spec/audit, Sonnet for QE/merger) | — | YES | This user's `feedback_model_selection_by_sdlc_layer` tuning |
| Fansipan-only-Opus rule | — | YES | Project-specific override |
| `feedback_no_claude_coauthor` commit trailer rule | — | YES | This user's git workflow |
| `feedback_git_workflow_solo` (commit-to-main, conventional prefixes) | — | YES | Solo-dev assumption [panel:E1 F11] |
| PARANOIA-BUST + DO-NOT-DELEGATE preambles | — | YES | Tuned to specific Opus 4.6/4.7 misbehaviors [panel:E3 §5] |

**Operator-specific does not mean wrong**. It means the rule was learned from a specific incident and may not generalize. Other users importing `opinions/` get a reasoned starting point with the option to opt out [panel:E1 F10 recommended resolution].

## 6. Worktree-spawn caveat

The pattern is real; the headline number does not generalize [PANEL-INTEGRATION.md §2.6]. Independent corroborators support parallel worktrees as a productivity primitive:

- `obra/superpowers` ships **Using Git Worktrees** as Phase 2 of its 7-phase workflow with 169,961★ of usage signal [Source: https://github.com/obra/superpowers; docs/research/06-ecosystem-and-superpowers.md §2.2].
- Chinese big-tech practitioner articles (`blog.ccino.org`, Meta-engineer commentary) cite the worktree pattern through the *one-task-per-branch* discipline [Source: docs/research/06-ecosystem-and-superpowers.md §5.2; panel:E4 §6.3].
- Boris Cherny endorses the workflow in public Threads posts [Source: https://www.threads.com/@boris_cherny/post/DWfjtLTFBhu/use-git-worktrees-claude-code-ships-with-deep-support-for-git-worktrees]. The "259 PRs in 30 days" framing is **dropped from this charter** — it was miscited in v0.1 (the cited Threads URL does not contain that statistic) and the figure itself is vendor-internal [docs/review/v1.1/CITATIONS-FIXED.md §5; panel:E3 §6; panel:E4 §3 row 4].

**v1 cap: 3 parallel sessions.** [panel:E3 §6; PANEL-INTEGRATION.md §2.6]. Above 3, the human supervisor's own context budget becomes the bottleneck (the supervisor has finite context too, per docs/research/02-sdlc-methodology.md §4.2). API spend climbs ~5× while throughput climbs ~2×. Steve Yegge's "Merge Wall" hits when cross-worktree dependencies surface [Source: docs/research/04-community-patterns.md §7]. The merge-wall caveat is shipped in CLAUDE.md alongside the cap.

## 7. Eval skeleton commitment

The charter commits the library to ship a 5-task golden eval in v1 P0, not as deferred infrastructure [panel:E2 M6; panel:E5 §2; docs/research/07-evals-and-learning-loops.md §8.1]. Without this, every other P0 ships unverified.

**What v1 ships** [Source: docs/research/07-evals-and-learning-loops.md §2.3]:

```
claude-skills/
├── promptfooconfig.yaml             # root eval config
├── tests/
│   ├── _fixtures/                   # synthetic projects (tiny-go-cli, small-react-app, system-change-monorepo)
│   ├── audit/tasks.yaml             # 3-5 golden tasks per skill
│   ├── anti-fantasy-rules/tasks.yaml
│   ├── governance-pack/tasks.yaml
│   ├── safety-hooks-bundle/tasks.yaml
│   └── worktree-spawn/tasks.yaml
└── .github/workflows/skills-eval.yml
```

**SLOs the library is held to** [Source: docs/research/07-evals-and-learning-loops.md §5, §8]:

- Every P0 skill ships with `tests/<skill>/tasks.yaml` containing 3–5 golden tasks [§8.2].
- Default grader is `llm-rubric` (procedural) / `factuality` (spec-conformance) / `g-eval` (reasoning), pinned to `claude-haiku-4-5-<minor-version>` to prevent vendor-side model swaps from masquerading as skill regressions [§3.4, §8.5].
- **Lesson observed → regression test landed: ≤24 hours** [§5.2]. The `lessons.md` discipline is paired with `tools/replay-to-test.sh` to convert real failures into Promptfoo tasks. Without an SLO, `lessons.md` is a sticky note.
- `safe-spawn-claude.sh` self-tests under `tests/safe-spawn/` covering: missing-DONE-token (exit 5), empty-output-file (exit 6), token-burn-without-output (exit 7) [§7.2; cites `feedback_silent_fail_token_burn` 2026-04-21 incident].
- Smoke run (1 task per skill) on every PR; full run (28+ tasks) on push to main; estimated CI cost ~$1 per smoke, ~$3.50 per full run with Sonnet model under test + Haiku grader [§3.3, §6.2].
- Every eval ships a contamination probe — gold-patch-by-ID test that fails when the eval input contains the reference solution verbatim [feat:eval-contamination-probe v2.0 P1 #5; see [`core/eval-contamination-probe/`](../../../core/eval-contamination-probe/README.md)].

**What is explicitly DEFERRED to v1.2 or later** [Source: docs/research/07-evals-and-learning-loops.md §8.8]:

- A/B / canary / shadow traffic experiments (Hamel L3 — no production traffic for a CLI library).
- OpenTelemetry traces (Phoenix-style) — overkill for shell-driven library.
- Custom data viewer — `claude --resume` + JSONL grep covers 80% at 0% cost.
- Generic-benchmark scoring (MMLU, BLEU, ROUGE) — Eugene Yan's explicit anti-pattern [Source: https://eugeneyan.com/writing/llm-patterns/].
- 1–5 quality scale — Hamel mandates binary-pass-fail with critique [Source: https://hamel.dev/blog/posts/field-guide/].
- Monte Carlo / statistical-significance testing — `wshobson/agents` has it [Source: https://github.com/wshobson/agents]; add when N(skills) > 25.

## 8. Out-of-scope, non-goals, roadmap pointer

**Out-of-scope.** The charter is not a Spec-Kit competitor [panel:E1 F14]; not an `oh-my-openagent`-style multi-model harness [Source: docs/research/04-community-patterns.md §9]; not a custom edit tool, not a `claude` CLI alternative, not an SDK fork. Plugin marketplace packaging is deferred to v1.2 once the spine stabilises. AGENTS.md output is not produced — Claude Code does not read it [Source: docs/research/05-authoring-format.md §8] — but `@AGENTS.md` import is supported for cross-tool projects.

**Non-goals.** The charter does not replace the user's existing memory system (auto-memory + neural-memory + MEMORY.md + lessons.md coexist). It does not enforce vendor lock-in to one prompting style — principles must remain portable in spirit even where implementations cannot be (per the cross-tool portability matrix in docs/research/06-ecosystem-and-superpowers.md §6, only MCP-shaped tools and CLAUDE.md-style instructions cleanly transfer; sub-agents, hooks, and skills are Claude-Code-specific and we stop pretending otherwise).

**Living-document protocol.** Monthly review (not quarterly — Anthropic ships ~1 breaking primitive change per 6 weeks per docs/research/05-authoring-format.md §11) [panel:E1 F13]. Triggers: a skill in P0 or P1 has shipped and been used for ≥1 week of dogfood; Anthropic ships a new primitive that changes the §2.2 enforcement menu; a war story enters the corpus that the charter does not defend against; an operator-specific rule turns out to generalize (promote from `opinions/` to `core/`); the charter exceeds 500 lines (this file is itself subject to §2.1 context constraint). See `charter-rationale.md` §9 for the full review cadence.

**Roadmap pointer.** The 12–24-month roadmap is the companion `skills-roadmap-v1.1.md` produced by a separate Path-C Stage 2B sub-agent. P0 cuts from 8 to ~6 standalone primitives [panel:E1 F12; panel:E2 rec #1; panel:E3 §10]; SDLC spine skills are killed (rubric only); `audit-pe` folds into `audit-security`; eval skeleton is P0; library is partitioned per §5; `compat/superpowers.md` is P1. If a charter principle has no corresponding roadmap entry, the roadmap is incomplete. If a roadmap entry has no charter principle motivating it, the entry is suspect — verify or cut.

---

**End of charter v1.1.** Companion: [`charter-rationale.md`](./charter-rationale.md) — every decision and trade-off documented per panel finding.
