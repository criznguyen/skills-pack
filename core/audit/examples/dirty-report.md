# Audit report — `auth-rotate-2026-04-26` (BLOCK)

> Reference example. Demonstrates the report structure for a diff with real findings: 2 CRITICAL + 3 MEDIUM + 1 LOW, verdict BLOCK. Mirrors the V1.1-AUDIT.md style mandated by `core/audit/SKILL.md` and `core/audit/prompts/system.md` Step 7.

## Executive summary

- **ID:** `auth-rotate-2026-04-26`
- **Diff range:** `main...HEAD` (`a01b2c3..f9e8d77`, 412 lines added, 87 removed across 9 files)
- **Dimensions run:** `security`, `pe`
- **Auditor:** `claude-opus-4-7` (isolation: worktree)
- **Wall clock:** 268s
- **Verdict:** **BLOCK**

The diff implements a session-token rotation flow for the `/auth/rotate` endpoint. Two CRITICAL findings prevent merge: the new endpoint executes a raw SQL query built by f-string against `request.json["user_id"]` (`AUDIT-001`, SQLi), and the new role-elevation path is reachable without the `@require_admin` decorator (`AUDIT-002`, missing authorization). Three MEDIUM and one LOW round out the report. Counts: 2 CRITICAL / 0 HIGH / 3 MEDIUM / 1 LOW / 0 INFO. Charter v1.1 §6 zero-deferral applies — both CRITICAL findings must be resolved before re-audit.

## Checklist

### Security dimension

| Item | Status | Note |
|---|---|---|
| A1 SQL/NoSQL injection | [!] | See `AUDIT-001` — f-string SQL at `auth/handler.py:142` |
| A2 OS command injection | [-] | None |
| A3 Template injection | [-] | None |
| A4 LDAP/XPath/regex/header injection | [-] | None |
| A5 XSS | [-] | API returns JSON only |
| B1 Authentication bypass | [x] | `/auth/rotate` requires bearer token |
| B2 Token/secret in code | [x] | Verified |
| B3 Weak token construction | [!] | See `AUDIT-003` — JWT signed HS256 with shared secret of length 16 |
| B4 Session lifecycle | [x] | Old token marked revoked in `tokens` table on rotate |
| B5 Password handling | [-] | No password in path |
| C1 IDOR | [-] | Token rotation operates on caller's own token |
| C2 Endpoint authorization | [!] | See `AUDIT-002` — `/auth/rotate/admin` ships without `@require_admin` |
| C3 Mass assignment | [-] | None |
| C4 CSRF | [-] | API behind bearer auth; cookies not used |
| D1 Crypto algorithm | [x] | bcrypt(cost=12) for password hashes (unchanged) |
| D2 TLS posture | [x] | All outbound calls verified TLS-on |
| D3 Random source | [x] | `secrets.token_urlsafe(32)` for new tokens |
| D4 Encryption-at-rest | [-] | DB engine handles |
| E1 PII in logs | [!] | See `AUDIT-004` — `logger.info("rotated for %s", request.json)` includes email |
| E2 Verbose errors to client | [x] | Errors mapped via `app.errorhandler` |
| E3 Hardcoded sensitive data | [x] | None |
| E4 Cache headers | [x] | `Cache-Control: no-store` set on `/auth/*` |
| F1 SSRF | [-] | None |
| F2 Open redirect | [-] | None |
| F3 DNS rebinding | [-] | None |
| G1 Unsafe deserialisation | [-] | None |
| G2 Path traversal | [-] | None |
| G3 File upload | [-] | None |
| G4 Zip-slip | [-] | None |
| H1 CORS | [x] | Allowlist unchanged |
| H2 Security headers | [x] | Middleware unchanged |
| H3 Default credentials | [-] | None |
| H4 Cloud IAM | [-] | None |
| I1 Auth event logging | [x] | Login/rotate/revoke events emitted |
| I2 Log injection | [x] | Verified |
| I3 Tamper detection | [-] | Out of scope |
| J1 Prompt injection | [-] | None |
| J2 Tool exfiltration | [-] | None |
| J3 Sub-agent budget guard | [-] | None |
| J4 Hook bypass | [-] | None |
| J5 Identity assertion | [-] | None |
| K1 Dependency provenance | [x] | No new deps |
| K2 Typosquat | [-] | None |
| K3 Postinstall scripts | [-] | None |
| K4 Mutable tag | [-] | None |
| L1 .env committed | [x] | None added |
| L2 Secret in CI yaml | [x] | Verified |
| L3 Secret in logs | [x] | Verified |
| L4 Leaked secret rotation | [-] | None |
| M1 Auth-decorated endpoint test | [!] | See `AUDIT-005` — `/auth/rotate` ships without unauth-401 test |
| M2 Validator negative test | [x] | Present |
| M3 Crypto KAT | [-] | None |

**Security totals:** 12 passed · 5 findings · 33 N/A

### PE dimension

| Item | Status | Note |
|---|---|---|
| P1 Spec adherence | [x] | All criteria mapped |
| P2 Non-goal violation | [x] | Honoured |
| P3 Off-by-one | [x] | None |
| P4 Null handling | [x] | None |
| P5 Concurrency | [x] | Token-rotate is per-user-row UPDATE; no shared state |
| P6 Idempotency | [x] | Replay returns same new token within 30s |
| P7 Error swallowing | [x] | All paths return wrapped errors |
| P8 Float on money | [-] | No money path |
| P9 Time zones | [x] | UTC throughout |
| Q1 API contract drift | [x] | New endpoint; spec'd |
| Q2 DB schema | [x] | Additive index migration; backfill noted |
| Q3 Event schema | [-] | None |
| Q4 Configuration as contract | [x] | Documented |
| Q5 Public signature | [-] | None |
| R1 Retry policy | [-] | None |
| R2 Timeout | [x] | Set |
| R3 Circuit breaker | [-] | N/A |
| R4 Resource cleanup | [x] | Context-managed |
| R5 Graceful shutdown | [x] | Inherits app config |
| R6 Backpressure | [-] | None |
| S1 N+1 | [x] | Single UPDATE |
| S2 Index | [x] | Added in migration |
| S3 Unbounded result | [-] | Single-row return |
| S4 Quadratic | [x] | None |
| S5 Hot-path allocation | [x] | None |
| T1 Critical path logs | [x] | Logged |
| T2 Structured fields | [x] | trace-id propagated |
| T3 SLI metric | [x] | Rotate-success-ratio metric emitted |
| T4 Alert runbook | [x] | Linked |
| T5 Sensitive log content | [!] | Mirror of AUDIT-004; recorded under security dimension |
| U1 Public symbol docs | [x] | All new public functions documented |
| U2 Dead code | [x] | None |
| U3 Duplicated logic | [x] | None |
| U4 Cyclomatic | [x] | Largest: 9 |
| U5 Magic numbers | [x] | Constants extracted |
| U6 Naming | [x] | None misleading |
| V1 New behaviour test | [x] | Happy-path tests present |
| V2 Bug-fix test | [-] | Not a bug fix |
| V3 Mocked over real boundary | [-] | testcontainers used |
| V4 Private state in test | [x] | Public API only |
| V5 Flaky-by-design | [x] | Deterministic |
| W1 refactor discipline | [-] | feat: |
| W2 Decisions log | [x] | Present |
| W3 Spec-hash drift | [x] | Matches |
| W4 Sub-agent spawn discipline | [-] | None |
| W5 CRITICAL/HIGH deferral | [x] | No deferral attempted |
| X1 Verify passed | [x] | CI green |
| X2 No new TODOs | [!] | See `AUDIT-006` — `# TODO(security): rate-limit later` introduced at `auth/handler.py:171` |
| X3 Feature flag | [x] | Behind `AUTH_ROTATE_V2` flag |
| X4 Migration rollback | [x] | Documented |

**PE totals:** 33 passed · 1 finding · 16 N/A

## Findings

| id | severity | dimension | where | description (≤25 words) | recommended_fix (≤25 words) | references |
|---|---|---|---|---|---|---|
| AUDIT-001 | CRITICAL | security | `auth/handler.py:138-152` | Endpoint builds SQL with f-string against `request.json["user_id"]`; classic SQLi reachable by any authenticated caller. | Use parameterised query: `db.execute("UPDATE tokens SET ... WHERE user_id = %s", (user_id,))`. Drop the f-string entirely. | security-checklist A1; OWASP A03:2021; charter v1.1 §6 zero-deferral |
| AUDIT-002 | CRITICAL | security | `auth/handler.py:201-226` | New `/auth/rotate/admin` route calls `elevate_role()` without `@require_admin`; any authenticated user can self-promote. | Add `@require_admin` decorator at line 200 matching the pattern at `auth/handler.py:88`. Verify via 403-on-non-admin test. | security-checklist C2; threat-model §3.2 "role boundary"; charter v1.1 §6 |
| AUDIT-003 | MEDIUM | security | `auth/jwt.py:42-58` | JWT signed HS256 with secret of length 16 chars from `JWT_SECRET` env var; spec calls for ≥32-byte key. | Enforce min length 32 at module init: raise on shorter; rotate the secret per `decisions.md` runbook entry. | security-checklist B3; spec success criterion 4; NIST SP 800-131A |
| AUDIT-004 | MEDIUM | security | `auth/handler.py:165` | `logger.info("rotated for %s", request.json)` formats the entire request body, including `email`. PII leakage to logs. | Log only `user_id` (already non-PII per project) and `event=rotate`. Drop the body. | security-checklist E1; threat-model §4.1 "PII boundary" |
| AUDIT-005 | MEDIUM | security | `tests/auth/test_rotate.py:1-94` | Test file covers happy path only; no test asserts unauthenticated request returns 401. M1 demands negative test. | Add `def test_rotate_unauthenticated_returns_401()` exercising the route without bearer token. | security-checklist M1; skills-roadmap-v1.1.md P0-06 |
| AUDIT-006 | LOW | pe | `auth/handler.py:171` | New `# TODO(security): rate-limit later` introduced. The TODO marker contradicts X2 and risks deferral of a security control. | Either rate-limit now (preferred) or remove the TODO and file an issue with explicit owner + due date. | pe-checklist X2; charter v1.1 §6 anti-deferral framing |

## Sources

- charter v1.1 §6 (zero-deferral) — `docs/synthesis/v1.1/charter-v1.1.md`
- charter v1.1 §2.3 (independence-of-reviewer) — `docs/synthesis/v1.1/charter-v1.1.md`
- skills-roadmap-v1.1.md P0-06 (golden-task-eval) — same file
- security-checklist (A1, B3, C2, E1, M1) — `core/audit/prompts/security-checklist.md`
- pe-checklist X2 — `core/audit/prompts/pe-checklist.md`
- OWASP Top 10 2021 A03 (Injection) — https://owasp.org/Top10/A03_2021-Injection/
- NIST SP 800-131A — https://csrc.nist.gov/publications/detail/sp/800-131a/rev-2/final

> *Generated by AI during audit. Verify findings before relying on them.*

---

`AUDIT-DONE id=auth-rotate-2026-04-26 verdict=BLOCK findings=6`
