<!-- last-validated: 2026-04-28 -->

# Audit glossary

Canonical vocabulary for `core/audit`. Mirrors authoritative sources verbatim; read once at audit spawn (CI: PR base SHA via `$AUDIT_GLOSSARY_PATH`; local `/audit`: working-tree HEAD) and read-only to the auditor. If absent, the auditor falls back to prose vocabulary in `system.md` / `security-checklist.md` / `pe-checklist.md`.

Cite terms by reference in `description` / `recommended_fix` prose; do NOT embed glossary block content into `findings.json`, `decisions.md`, telemetry, or hook stderr (suppression mirrors audit-disclaimer §1.8).

## A. Severity vocabulary

| Severity | Meaning | Verdict gate |
|---|---|---|
| CRITICAL | Production data loss, RCE, auth bypass, PII leak | BLOCK; zero-deferral |
| HIGH | Privilege escalation, broken invariant, data corruption window | BLOCK; zero-deferral |
| MEDIUM | Defence-in-depth gap, contract drift, test gap on critical path | Negotiable; document |
| LOW | Code-smell that compounds risk, missing log, hardcoded value | Track; do not block |
| INFO | Observation, no required action | Informational |

Source: `core/audit/SKILL.md` §"Severity scale" + charter v1.1 §6.1. Drift detected by `glossary-consistency-check`. Zero-deferral on CRITICAL / HIGH is non-negotiable; severity-laundering is a charter §6 prohibited move.

## B. STRIDE primitives

| Letter | Threat | One-liner |
|---|---|---|
| S | Spoofing | Attacker assumes another identity (forged token, impersonation). |
| T | Tampering | Unauthorized modification of data or code in transit or at rest. |
| R | Repudiation | Action cannot be traced to actor (missing audit log, weak attribution). |
| I | Information Disclosure | Confidential data leaks to unauthorized parties. |
| D | Denial of Service | Resource exhaustion, ReDoS, crash-on-input, amplification. |
| E | Elevation of Privilege | Lower-privileged actor gains higher-privileged capabilities. |

Source: `core/audit/prompts/security-checklist.md` §"STRIDE". Tag inline as `STRIDE:S` … `STRIDE:E`, or `STRIDE:N/A` when genuinely orthogonal.

## C. Finding categories

OWASP Top 10 (2021): `A01` Broken Access Control · `A02` Cryptographic Failures · `A03` Injection · `A04` Insecure Design · `A05` Security Misconfiguration · `A06` Vulnerable & Outdated Components · `A07` Identification & Authentication Failures · `A08` Software & Data Integrity Failures · `A09` Security Logging & Monitoring Failures · `A10` SSRF.

PE checklist nouns: correctness · contract integrity · reliability · performance · observability · maintainability · test discipline · process integrity · pre-merge readiness.

A finding's `dimension` is `security` (OWASP / STRIDE) or `pe` (PE noun). Overlap is expected (60–70% per panel §1.4); pick the dominant dimension and mention the other in `description`.

## D. Banned phrases

- `vulnerability` without an attack vector — name the vector.
- `hacker` — use *attacker* or *threat actor*.
- `best-practice` — name the concrete practice and its source.
- `industry-standard` — cite the standard (RFC, NIST SP, OWASP page).
- `should always` — describe the conditional and its trigger instead.
- `never do` — describe the failure mode and its severity instead.

