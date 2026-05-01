# Principle-engineer (PE) checklist — `dimension=pe`

Walk top-to-bottom. For each item: `[x]` (passed with evidence), `[!]` (finding), or `[-]` (not applicable, with reason).

The PE dimension covers correctness, maintainability, performance, reliability, observability, contract integrity, and the SDLC-process boundary. The 60–70% overlap with `security` is expected per panel finding [E3 row 18]: a perf bug under load is often a DoS finding; a contract drift is often a privilege boundary mistake. Pick the dimension that *primarily* describes the defect; allow a second finding under the other dimension only when the framings genuinely differ.

## P. Correctness

P1. **Spec adherence.** Every named success criterion in `<spec_path>` is implemented and demonstrably reached by at least one code path in the diff. Default severity: **HIGH** if a criterion is unimplemented.

P2. **Non-goal violation.** A named non-goal in the spec is implemented anyway (scope creep). Default severity: **MEDIUM**.

P3. **Off-by-one / boundary.** Loop bounds, slice indices, range comparisons (`<` vs `<=`), `len()`-based stops on possibly-empty inputs. Default severity: **HIGH**.

P4. **Null / undefined handling.** A function dereferences a value that the type system or upstream contract permits to be null/None/undefined. Default severity: **HIGH**.

P5. **Concurrency invariants.** New shared mutable state without a lock; double-checked locking; map iterated while mutated; goroutine without context cancellation. Default severity: **HIGH**.

P6. **Idempotency on retried operations.** Webhook handlers, queue consumers, payment callbacks — re-processing the same input must not double-apply effects. Default severity: **HIGH**.

P7. **Error swallowing.** `try/except: pass`, `catch (e) {}`, ignored error returns, `_, _ = func()` discarding a meaningful error. Default severity: **HIGH**. (Same code shape as security E2, but framed as correctness here.)

P8. **Floating-point on money.** Currency stored or arithmetic-on as `float`/`double` instead of `Decimal`/integer minor units. Default severity: **HIGH**.

P9. **Time-zone discipline.** New `datetime` without explicit tz; comparison of naive and aware datetimes; `datetime.now()` instead of `datetime.now(tz=UTC)`. Default severity: **MEDIUM**.

## Q. Contract integrity

Q1. **API contract drift.** Public endpoint changes its request schema, response schema, or status-code semantics without a corresponding spec update or version bump. Default severity: **HIGH**.

Q2. **Database schema migration.** New migration drops a column / changes a type / adds a `NOT NULL` without backfill, or runs lock-incompatible DDL on a hot table. Default severity: **CRITICAL**.

Q3. **Event/queue payload drift.** Topic schema changes without consumer update / version. Default severity: **HIGH**.

Q4. **Configuration as contract.** New required env var without a default and without `decisions.md` note that production deploy must add it. Default severity: **HIGH**.

Q5. **Public function signature change.** Exported symbol's signature changed without bumping the package version (semver violation). Default severity: **MEDIUM** (HIGH for an SDK).

## R. Reliability & failure handling

R1. **Retry policy.** New external call without exponential backoff + jitter + cap; or unbounded retry that can DDoS the dependency. Default severity: **HIGH**.

R2. **Timeout missing.** External call without an explicit timeout; infinite-blocking RPC. Default severity: **HIGH**.

R3. **Circuit breaker / bulkhead.** Critical dependency wired without circuit breaker where the system is multi-tenant. Default severity: **MEDIUM**.

R4. **Resource cleanup.** File/socket/DB-connection opened without `defer`/`with`/`try-with-resources`. Default severity: **MEDIUM**.

R5. **Graceful shutdown.** New long-running goroutine/thread without context/cancel hookup; HTTP server lacking shutdown handler for in-flight requests. Default severity: **MEDIUM**.

R6. **Backpressure / queue depth.** New unbounded channel/queue/buffer; producer with no slow-consumer signal. Default severity: **MEDIUM**.

## S. Performance

S1. **N+1 query.** Loop issuing one DB query per item where a join/IN-clause would suffice. Default severity: **HIGH** if on a request-path, **MEDIUM** elsewhere.

S2. **Missing index.** Migration adds a column queried by `WHERE`/`ORDER BY` with no covering index. Default severity: **MEDIUM**.

S3. **Unbounded result set.** Endpoint returns rows without `LIMIT`/pagination on a table that can grow. Default severity: **HIGH**.

S4. **Quadratic algorithm on growable input.** Nested loop / quadratic regex over user-controlled length. Default severity: **HIGH**.

S5. **Excessive allocation in a hot path.** Per-request `new` of a heavy object (parser, pool client) that should be reused. Default severity: **MEDIUM**.

## T. Observability

T1. **Critical path without logs.** New error branch with no `log.error` / equivalent. Default severity: **MEDIUM**.

T2. **Missing structured fields.** Logs printed as plain strings on a path that other services parse as JSON; or missing trace-id / request-id propagation. Default severity: **MEDIUM**.

T3. **Metrics for new SLI.** Spec names an SLI; diff does not emit the metric. Default severity: **MEDIUM**.

T4. **Alert without runbook.** New PagerDuty/Slack alert added without a `docs/runbook/<alert>.md`. Default severity: **LOW**.

T5. **Sensitive log content.** Mirrors security E1 — record once, under whichever dimension is more load-bearing for this diff.

## U. Maintainability

U1. **Public symbol without docstring.** New exported function/class without a one-line purpose statement. Default severity: **LOW**.

U2. **Dead code in diff.** Functions/branches that no caller can reach; commented-out blocks; "added for the X flow" comments. Default severity: **LOW**.

U3. **Duplicated logic.** Three or more near-identical blocks added that should share a helper — but only if extraction does not introduce premature abstraction (per CLAUDE.md "three similar lines is better than a premature abstraction"). Default severity: **LOW**.

U4. **Cyclomatic complexity.** New function with cyclomatic > 15 (or project-defined threshold). Default severity: **MEDIUM**.

U5. **Magic numbers.** Hardcoded constants (timeouts, limits, retry counts) without a named constant or env-var indirection where the spec says they should be tunable. Default severity: **LOW**.

U6. **Naming.** Identifier names that mislead about semantics (`getUser` that mutates, `is_valid` that throws). Default severity: **LOW**.

## V. Test discipline

V1. **No new test for new behaviour.** Diff adds a feature/branch and adds zero tests. Default severity: **HIGH** for `feature` task class, **MEDIUM** for bug-fix without `bug-fix-with-failing-test`.

V2. **Bug-fix without failing test in prior commit.** For a `fix(...)` commit, no test was added in the same diff that would have failed before the fix (per skill P1-08). Default severity: **MEDIUM**.

V3. **Mocked over an integration boundary the project insists on real.** Test mocks a database when the project's convention is testcontainers (per the project's existing test patterns). Default severity: **MEDIUM**.

V4. **Test imports production code's private state.** New test reaches into private state (`_internal.foo`) instead of asserting via the public surface. Default severity: **LOW**.

V5. **Flaky-by-design.** New test depends on wall-clock timing, network availability, or non-deterministic ordering. Default severity: **MEDIUM**.

## W. Process integrity

W1. **`refactor(scope):` discipline.** A commit tagged `refactor(...)` modifies tests or changes behaviour. Default severity: **MEDIUM**. [Source: skills-roadmap-v1.1.md P1-09]

W2. **Decisions log gap.** A non-trivial choice is made (algorithm pick, library pick, schema layout) without an entry in `decisions.md`. Default severity: **LOW** (MEDIUM if the choice is irreversible).

W3. **Spec-hash drift.** Spec was modified after implementation began but the implementation does not reflect the new spec. Default severity: **HIGH** if the spec change names a security or correctness criterion.

W4. **Sub-agent spawn discipline.** Code spawns helper processes without using the project's required wrapper (`safe-spawn-claude.sh` for this user). Mirrors security J3; record once.

W5. **CRITICAL/HIGH deferral attempt.** Diff or commit message defers a charter-§6 zero-deferral severity ("known-issue, follow-up later"). Default severity: **HIGH**.

## X. Pre-merge readiness

X1. **Verify command passes.** Repo's `make verify` (or equivalent — see `core-config` §2 verification rule) was run and exited 0 prior to audit. Auditor should require evidence (CI status, recorded output). Default severity: **HIGH** if no evidence.

X2. **No `TODO` / `FIXME` / `XXX` introduced.** New TODO comments in production code. Default severity: **LOW** (MEDIUM if marked `TODO(security)`).

X3. **Feature flag wiring.** New behaviour shipped without a feature flag where the spec or `decisions.md` calls for one. Default severity: **MEDIUM**.

X4. **Migration rollback.** New DB migration without a documented rollback path. Default severity: **MEDIUM**.

---

End of PE checklist. Proceed to system.md Step 4 (record findings) and Step 5 (verdict).
