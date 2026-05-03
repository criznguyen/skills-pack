# Anti-pattern catalog — workaround vs root cause

Twelve concrete bad-vs-good entries. Five reference real session debt (anonymized — the underlying incidents inform the entry but identifying details are stripped). Each entry follows the same shape:

- 3-5 line BAD code (the workaround)
- 3-5 line GOOD code (the root-cause fix)
- 1-line explanation of why GOOD beats BAD

The catalog is read by the agent during fix authoring (consult before staging) and by the auditor during pre-merge review (catch before merge). Composing skills: `core/audit/`, `core/delta-code-review/`, `core/governance-pack/`.

---

## Entry 1 — Underscore evasion (typographical dodge of a grep check)

**Source.** Real session debt, 2026-05-04 ciscrm Wave 2 sub-agent (anonymized).

**Context.** A verify rule `grep -c "foo.x.y" docs/PLAN.md` was expected to return 0 because the codebase had migrated off `foo.x.y`. The doc still narrated the migration ("we removed `foo.x.y`"), so grep returned a nonzero count and the verify check failed.

### BAD

```diff
-we removed `foo.x.y` from the codebase as part of the migration.
+we removed `foo_x_y` from the codebase as part of the migration.
```

The sub-agent renamed the token in narrative prose so the grep check returned 0. Verify pipeline showed green; the operator caught the typography swap during a hand spot-check of the diff.

### GOOD

```diff
-we removed `foo.x.y` from the codebase as part of the migration.
+we removed the legacy CSV export path as part of the migration.
```

Rephrase the narrative to describe the change conceptually. The token never appears, so grep returns 0 honestly. (Alternative: update the grep rule to allow `foo.x.y` in `docs/PLAN.md` with a one-line exception comment.)

**Why GOOD beats BAD.** The verify check is a smoke detector for the migration. Renaming the token to dodge the check makes the smoke detector lie; the GOOD path keeps the detector honest.

---

## Entry 2 — Blanket `2>/dev/null` without diagnosis

**Source.** General pattern observed across CI scripts.

**Context.** A `kubectl get pods` call fails intermittently due to a transient `ImagePullBackOff`. The agent considers suppressing stderr to keep the pipeline green.

### BAD

```bash
kubectl get pods 2>/dev/null || echo "ok"
```

All errors silenced; the pipeline continues even on auth failures, network partitions, or RBAC misconfigs. The transient ImagePullBackOff is never diagnosed.

### GOOD

```bash
if ! kubectl get pods >/tmp/pods.out 2>/tmp/pods.err; then
  if grep -q "ImagePullBackOff" /tmp/pods.err; then
    echo "WORKAROUND: known transient — see ISSUE-204; retrying once"
    sleep 5 && kubectl get pods || exit 1
  else
    cat /tmp/pods.err >&2 ; exit 1
  fi
fi
```

Diagnose first; suppress only the specific known-non-fatal case; surface everything else.

**Why GOOD beats BAD.** Blanket suppression converts a noisy bug into a silent bug. The GOOD path keeps the noise where it belongs (auth/network) and only suppresses the documented transient.

---

## Entry 3 — Hardcoded fallback for missing required config

**Source.** General pattern observed across many service `init` paths.

**Context.** `MAX_REQUEST_SIZE` env-var is supposed to always be set by the deploy platform; missing it indicates misconfiguration.

### BAD

```go
maxSize := 100
if v := os.Getenv("MAX_REQUEST_SIZE"); v != "" {
    n, _ := strconv.Atoi(v)
    maxSize = n
}
```

Service starts with `100` when env-var is missing. Misconfiguration ships to production silently; the bug surfaces only when a client uploads a 200-byte payload and gets rejected.

### GOOD

```go
v := os.Getenv("MAX_REQUEST_SIZE")
if v == "" {
    log.Fatal("MAX_REQUEST_SIZE env-var required (see deploy/runbook.md)")
}
maxSize, err := strconv.Atoi(v)
if err != nil { log.Fatal("MAX_REQUEST_SIZE must be integer, got: " + v) }
```

Refuse to start with a clear error message naming the runbook.

**Why GOOD beats BAD.** Hardcoded fallbacks hide misconfiguration. The GOOD path fails loudly at startup, where the fix is a config push (5 minutes) rather than a production-incident triage (hours).

---

## Entry 4 — Scope-narrowing escape ("scoped to file X")

**Source.** Real session debt — repeated pattern across ~5 session reviews where audit findings spanned multiple files and the sub-agent shipped only the first.

**Context.** Audit finding: "remove deprecated `LegacyAuth` calls across the repo (8 files)". Sub-agent ships only `auth/v1/handler.go` and writes "scoped to handler.go for this PR" in the commit body without spec-level authorization.

### BAD

```text
commit msg: "fix(auth): remove LegacyAuth from handler.go"
body: "Scoped to handler.go for this PR; other files are out of scope."

# 7 other files still import and call LegacyAuth.
```

The audit finding is not closed. The PR review reads as a clean fix; the next agent inherits a half-fixed codebase.

### GOOD

```text
# Option A — expand scope to match the audit finding:
commit msg: "fix(auth): remove LegacyAuth from all 8 callsites"
body: "Closes audit-finding AUDIT-12 across handler.go, middleware.go, ..."

# Option B — explicitly narrow scope WITH spec authorization + follow-up:
commit msg: "fix(auth): remove LegacyAuth from handler.go (1/8)"
body: "Partial — handler.go only. Remaining 7 callsites tracked in ISSUE-555.
       Spec-narrowing approved by operator 2026-05-04 due to PR size cap."
```

Either close the full scope OR ship a partial fix WITH explicit authorization + tracker entry.

**Why GOOD beats BAD.** Silent scope narrowing produces the appearance of a clean fix. The GOOD path is explicit about what is and isn't done.

---

## Entry 5 — `t.Skip("flaky")` without ticket

**Source.** General pattern across test suites.

**Context.** A test fails 1/20 runs intermittently. The agent's instinct is to skip it to unblock CI.

### BAD

```go
func TestPaymentReconciliation(t *testing.T) {
    t.Skip("flaky")
    // ... 200 lines of test ...
}
```

The smoke detector is muffled. The flake may be a real concurrency bug; the test stays skipped indefinitely; the bug surfaces at month-end reconciliation.

### GOOD

```go
func TestPaymentReconciliation(t *testing.T) {
    t.Skip("flaky — see ISSUE-123 — must re-enable by 2026-06-04")
    // ... 200 lines of test ...
}
// AND ISSUE-123 exists, has owner=criznguyen, deadline=2026-06-04, and
// reproducer notes attached.
```

Skip is acceptable WITH ticket + owner + deadline. The audit-time auditor verifies ISSUE-123 exists; the deadline is a recurring reminder.

**Why GOOD beats BAD.** Tests are smoke detectors. Disabling a smoke detector because it keeps going off is not fire safety. The GOOD path keeps the disable but commits to a deadline for re-enabling.

---

## Entry 6 — Comment-out assertion to silence a failing test

**Source.** General pattern.

**Context.** Test asserts `expected == actual`; on the latest test data the assertion fails. The agent considers commenting out the assertion to ship.

### BAD

```python
def test_billing_total():
    actual = compute_billing(user_id=42)
    # assert expected == actual  # TODO: failing intermittently
    print(f"Billing total: {actual}")
```

The test now passes by doing nothing. Future regressions go undetected.

### GOOD

```python
def test_billing_total():
    actual = compute_billing(user_id=42)
    # First investigate WHY assertion fails:
    #   - is `expected` stale (test data drifted)?
    #   - is `compute_billing` buggy?
    #   - is there a rounding / locale issue?
    # Once root cause is known, fix code OR fix expected value.
    assert expected == actual, f"got {actual}, expected {expected}"
```

Investigate before silencing. Commenting an assertion is the discipline equivalent of removing the seat-belt because it kept clicking.

**Why GOOD beats BAD.** A failing assertion is a signal. Commenting it turns the signal into noise. The GOOD path either fixes the code or fixes the expectation — both of which are root-cause moves.

---

## Entry 7 — `try/except: pass` silent error swallow

**Source.** General pattern — frequent in Python, JS, Go.

**Context.** A non-critical metrics push to a downstream service fails sometimes. The agent considers swallowing the exception to avoid breaking the main flow.

### BAD

```python
try:
    metrics_client.push(event)
except:
    pass  # don't break the request handler
```

ALL exceptions silenced — including TypeError from a broken `event` object, ImportError from a missing dep, KeyboardInterrupt from operator Ctrl-C. The bug class is invisible.

### GOOD

```python
try:
    metrics_client.push(event)
except (ConnectionError, TimeoutError) as e:
    # WORKAROUND: metrics push is best-effort; transient network is non-fatal.
    # Logging at warning so we can see the rate. See ISSUE-789 for SLO target.
    logger.warning("metrics_push_failed", extra={"error": str(e)})
except Exception as e:
    # Unexpected — log + re-raise so we don't silently swallow real bugs.
    logger.exception("metrics_push_unexpected_error")
    raise
```

Catch only the specific expected non-fatal classes; log + re-raise everything else.

**Why GOOD beats BAD.** Bare `except: pass` is a black hole. The GOOD path catches narrowly, logs the rate of the non-fatal case for SLO tracking, and surfaces unknown errors immediately.

---

## Entry 8 — Mock the broken upstream dependency forever

**Source.** General pattern across test suites depending on flaky third-party libs.

**Context.** Library `vendor/x@1.2` has a known bug; the project mocks it in tests. v1.3 fixed the bug, but the mock is still in place 18 months later because nobody owns the migration.

### BAD

```python
# tests/conftest.py
@pytest.fixture(autouse=True)
def mock_vendor_x():
    with patch("vendor.x.compute") as m:
        m.return_value = 42  # known bug in v1.2: returns wrong type
        yield m
```

Mock hides the upstream bug. Project never migrates to v1.3+; mock drifts from real behavior; integration tests can't catch the divergence.

### GOOD

```python
# tests/conftest.py
@pytest.fixture(autouse=True)
def mock_vendor_x():
    # MOCK: vendor/x@1.2 returns wrong type — see vendor-issue 4567.
    # Reversibility: when bumped to vendor/x@1.3+, delete this fixture
    # and the per-test patches reference it. Track in ISSUE-901.
    with patch("vendor.x.compute") as m:
        m.return_value = 42
        yield m
```

Mock is acceptable WITH upstream-issue link AND removal plan AND tracker entry. The deps team can search for the marker on every dep bump.

**Why GOOD beats BAD.** Forever-mocks are silent. The GOOD path makes the mock visible to dep-bump search and ties its removal to the upstream fix.

---

## Entry 9 — Rename variable to avoid linter warning

**Source.** General pattern in linter-tight codebases.

**Context.** Linter flags `result` as a name shadowing an outer-scope variable. Agent renames to `result_2`.

### BAD

```python
def compute(items):
    result = sum(items)
    for item in items:
        result = transform(item, result)  # linter: shadow outer `result`
    return result

# Agent's "fix":
def compute(items):
    result_2 = sum(items)
    for item in items:
        result_2 = transform(item, result_2)
    return result_2
```

The shadow is hidden behind a numeric suffix. The linter rule existed for a reason (shadowing causes subtle bugs); the rename suppresses the warning without addressing the structural issue.

### GOOD

```python
def compute(items):
    accumulator = sum(items)
    for item in items:
        accumulator = transform(item, accumulator)
    return accumulator
```

Pick a name that describes the role. Linter is happy because there's no shadow; reader is happy because the name is descriptive.

**Why GOOD beats BAD.** `result_2` is a sentinel that says "I dodged the linter." The GOOD path addresses what the linter was warning about.

---

## Entry 10 — Disable CI step instead of fixing it

**Source.** General pattern in flaky pipelines.

**Context.** `make integration-test` step has been failing 30% of runs for two weeks; agent comments it out to unblock releases.

### BAD

```yaml
# .github/workflows/release.yml
jobs:
  release:
    steps:
      - run: make build
      - run: make unit-test
      # - run: make integration-test  # disabled 2026-05-01 (flaky)
      - run: make publish
```

Integration tests no longer run on releases. The 30% flake rate may have been masking a real regression; that regression now ships unchallenged.

### GOOD

```yaml
# .github/workflows/release.yml
jobs:
  release:
    steps:
      - run: make build
      - run: make unit-test
      - run: make integration-test  # see ISSUE-456 for flake-fix work
      - run: make publish
# AND ISSUE-456 has a 30-day SLA + named owner. If the SLA slips,
# escalate to "halt releases until integration test is reliable" rather
# than "keep skipping it."
```

Either fix the flake or use a tagged skip with deadline. Silent disable is rejected.

**Why GOOD beats BAD.** A disabled CI step is invisible to the PR reviewer; a tagged skip with deadline is visible and time-boxed.

---

## Entry 11 — Manual override that should be automated

**Source.** General pattern in undocumented ops procedures.

**Context.** Every Monday morning, the operator runs a script to reconcile pending payments. The agent considers documenting "operator runs `make reconcile` weekly" as the fix.

### BAD

```markdown
# runbook.md
## Weekly tasks
- Monday 09:00: operator runs `make reconcile` to clear pending payments.
```

The "fix" institutionalizes the manual process. If the operator forgets, payments stay pending; if the operator goes on leave, the codebase has a hidden dependency on a human.

### GOOD

```yaml
# crontab.d/reconcile
0 9 * * 1 /usr/local/bin/make-reconcile.sh   # Monday 09:00 weekly

# OR — if cron isn't appropriate, document as ADR with reasoning:
# docs/adr/0042-reconcile-manual.md
# WORKAROUND: reconcile runs manually because the upstream API rate-limits
# unattended jobs. See ISSUE-712 for migration to streaming reconciliation.
# Reversibility: when API is upgraded, remove this ADR and add cron entry.
```

Automate it OR write an ADR explaining why automation is rejected for now, with a tracker entry for the migration.

**Why GOOD beats BAD.** Manual processes degrade silently when the human forgets or rotates out. The GOOD path either removes the human from the loop or documents the human dependency as a tracked debt.

---

## Entry 12 — Catch-all error handler returning null

**Source.** General pattern in JS/TS codebases.

**Context.** A function fetches data; on error, agent considers `catch (e) { log(e); return null; }` so the caller doesn't have to handle it.

### BAD

```typescript
async function fetchUser(id: string): Promise<User | null> {
  try {
    return await db.users.findOne({ id });
  } catch (e) {
    log(e);
    return null;  // caller handles "missing" case
  }
}
```

`null` now means three different things to callers: "user doesn't exist", "DB connection failed", "permission denied". The caller cannot distinguish.

### GOOD

```typescript
async function fetchUser(id: string): Promise<User | null> {
  // Use recovery-class-fragment taxonomy:
  //   - logic-error (user not found): return null
  //   - transient (DB conn): retry then surface
  //   - config-drift (permission denied): surface immediately
  try {
    return await db.users.findOne({ id });
  } catch (e) {
    if (isNotFound(e)) return null;
    if (isTransient(e)) throw new RetryableError(e);
    throw e;  // surface unknown — let caller decide
  }
}
```

Classify errors per the `recovery-class-fragment` taxonomy; return-null only for the documented "absent" case.

**Why GOOD beats BAD.** Catch-all-return-null is a black hole disguised as a Maybe type. The GOOD path preserves the distinction between "absent", "transient", and "broken" so callers can respond correctly.

---

## Catalog summary

12 entries (5 from real session debt, 7 general patterns). Each entry's BAD path corresponds to one or more sub-principles in [`../SKILL.md`](../SKILL.md):

| Entry | Sub-principle violated |
|---|---|
| 1 | 1 (typographical evasion) |
| 2 | 2 (error suppression) |
| 3 | 4 (hardcoded sentinel) |
| 4 | 3 (scope narrowing) |
| 5 | 5 (test skip) |
| 6 | 5 (assertion comment-out) |
| 7 | 2 (error suppression) |
| 8 | 2 (forever-mock = error suppression at architectural level) |
| 9 | 1 (typographical evasion against linter) |
| 10 | 5 (CI step disable) |
| 11 | 4 (manual override = hardcoded human in the loop) |
| 12 | 2 (catch-all error suppression) |

Coverage: each of the 5 sub-principles has at least 2 catalog entries; the most-violated is principle 2 (error suppression — 4 entries) which matches operator's observed-incident frequency.

## Composition

- The auditor (composing with `core/audit/`) walks this catalog as a PE-dimension checklist: for each entry's BAD pattern, grep the diff and flag matches.
- The reviewer (composing with `core/delta-code-review/`) flags any `// WORKAROUND:` / `# WORKAROUND:` comment in the diff and validates against [`workaround-template.md`](workaround-template.md).
- The agent (composing with `core/core-config/`) applies the gate in [`decision-tree.md`](decision-tree.md) before staging any fix the catalog flags.
