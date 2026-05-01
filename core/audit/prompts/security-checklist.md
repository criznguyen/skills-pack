# Security checklist — `dimension=security`

Walk top-to-bottom. For each item: `[x]` (passed with evidence), `[!]` (finding, record per `system.md` Step 4), or `[-]` (not applicable, with reason).

The checklist is grouped against an OWASP-Top-10-2021-aligned spine plus three adapter classes (LLM/agent, supply chain, secrets) the panel called out as recurrently missed [E1 F5; E3 §3.2]. Severity guidance per item is the **default** assignment if the item triggers; you may shift one level up if the threat-model marks the surrounding asset as high-value.

## Tagging requirement (ADOPT-03 v1.1.1) — OWASP Top 10 + STRIDE

For every security finding, the audit MUST tag both:

- `OWASP:A0X` — applicable Top 10 (2021) category (or `OWASP:N/A` if genuinely orthogonal).
- `STRIDE:<letter>` — applicable threat category (or `STRIDE:N/A`).

The audit verdict MUST cite at least one OWASP or STRIDE category per HIGH/CRITICAL finding. MEDIUM/LOW/INFO may be `N/A` only when genuinely orthogonal — default toward tagging.

### OWASP Top 10 (2021)

| Tag | Name | One-liner |
|---|---|---|
| `OWASP:A01` | Broken Access Control | Authorization missing, IDOR, privilege checks bypassed. |
| `OWASP:A02` | Cryptographic Failures | Weak/absent crypto, plaintext secrets, exposed sensitive data. |
| `OWASP:A03` | Injection | SQL/NoSQL/OS/template/LDAP/XSS — untrusted input reaches an interpreter. |
| `OWASP:A04` | Insecure Design | Missing threat modeling, unsafe-by-construction patterns, no rate limiting. |
| `OWASP:A05` | Security Misconfiguration | Default creds, permissive CORS, missing headers, verbose errors. |
| `OWASP:A06` | Vulnerable & Outdated Components | Unpinned deps, EOL libs, known-CVE versions, supply-chain risk. |
| `OWASP:A07` | Identification & Authentication Failures | Weak auth, session fixation, brute-forceable, MFA bypass. |
| `OWASP:A08` | Software & Data Integrity Failures | Unsafe deserialisation, unsigned updates, CI/CD tampering. |
| `OWASP:A09` | Security Logging & Monitoring Failures | Auth events unlogged, no alerts, log injection, no tamper detection. |
| `OWASP:A10` | Server-Side Request Forgery (SSRF) | User-controlled URL fetch, open redirect, metadata-service exposure. |

Tag form inline: `OWASP:A03`. Use `OWASP:N/A` when none applies.

### STRIDE

| Letter | Threat | One-liner |
|---|---|---|
| S | Spoofing | Attacker assumes another identity (forged token, impersonation). |
| T | Tampering | Unauthorized modification of data or code in transit or at rest. |
| R | Repudiation | Action cannot be traced to actor (missing audit log, weak attribution). |
| I | Information Disclosure | Confidential data leaks to unauthorized parties. |
| D | Denial of Service | Resource exhaustion, ReDoS, crash-on-input, amplification. |
| E | Elevation of Privilege | Lower-privileged actor gains higher-privileged capabilities. |

Tag forms inline: `STRIDE:S`, `STRIDE:T`, `STRIDE:R`, `STRIDE:I`, `STRIDE:D`, `STRIDE:E`. Use `STRIDE:N/A` when none applies.

### Usage

Include both `OWASP:A0X` and `STRIDE:<letter>` (or `:N/A`) inline in the finding's `description` or under the structured `tags` field of `schemas/finding.json`. Calibration on the audit-evals tasks should verify ≥80% A0X coverage on security findings (charter v1.1 §9 promotion gate for ADOPT-03).

## A. Injection (OWASP A03:2021)

A1. **SQL/NoSQL injection.** Every database query in the diff uses parameterised queries or an ORM with bind variables. String concatenation of user input into a query string is automatic CRITICAL. Default severity: **CRITICAL**. [Source: https://owasp.org/Top10/A03_2021-Injection/]

A2. **OS command injection.** Calls to `os.system`, `subprocess.run(..., shell=True)`, `exec`, `eval`, backticks, or any shell-interpolating function with non-constant input. Default severity: **CRITICAL**.

A3. **Template injection.** User input rendered through Jinja2/ERB/Handlebars without escaping; `safe`/`raw` filters applied to user content. Default severity: **HIGH**.

A4. **LDAP/XPath/regex/header injection.** User input flows into LDAP filters, XPath queries, regex constructed at runtime (ReDoS), or HTTP headers (CRLF). Default severity: **HIGH**.

A5. **Cross-site scripting (XSS).** Templates render user data without contextual escaping; `innerHTML`, `dangerouslySetInnerHTML`, `v-html` applied to non-sanitised input. Default severity: **HIGH**.

## B. Broken authentication & session (OWASP A07:2021)

B1. **Authentication bypass.** A new code path that reaches a privileged operation without invoking the established auth middleware/decorator. Default severity: **CRITICAL**.

B2. **Token/secret in code.** API keys, signing keys, DB passwords, JWT secrets hardcoded or committed. Default severity: **CRITICAL**.

B3. **Weak token construction.** JWTs signed with `none`, with HS256 against a guessable secret, or without expiry. Sessions seeded with `Math.random()` / non-CSPRNG. Default severity: **HIGH**.

B4. **Session fixation/lifecycle.** Session ID not rotated on privilege change (login, role swap). Logout does not invalidate server-side state. Default severity: **HIGH**.

B5. **Password handling.** Plain bcrypt with cost factor < 10, MD5/SHA-1/raw-SHA-256 for password storage, password compared with non-constant-time `==`. Default severity: **HIGH**.

## C. Authorization (OWASP A01:2021)

C1. **Insecure Direct Object Reference (IDOR).** A handler accepts an ID parameter and returns the object without verifying the caller owns/has-permission-for it. Default severity: **CRITICAL**.

C2. **Privilege checks missing on a new endpoint.** New route added; no role/scope check on the handler. Default severity: **CRITICAL**.

C3. **Mass assignment.** Request body bound directly to a model that contains privileged fields (e.g. `is_admin`, `org_id`) with no allowlist. Default severity: **HIGH**.

C4. **CSRF protection.** State-changing endpoints reachable by `GET`, or `POST` without a CSRF token / SameSite cookie strategy. Default severity: **HIGH**.

## D. Cryptographic failures (OWASP A02:2021)

D1. **Crypto algorithm choice.** Use of MD5/SHA-1 for security purposes; DES/3DES/RC4 for symmetric encryption; ECB mode; static IV/nonce. Default severity: **HIGH**.

D2. **TLS posture.** New outbound HTTP call uses `http://` to a non-loopback host; `verify=False`/`InsecureSkipVerify`/`rejectUnauthorized: false`. Default severity: **HIGH**.

D3. **Random source.** Security-relevant tokens generated with non-cryptographic RNG (`random.random`, `Math.random`, `rand()` without seeding from a CSPRNG). Default severity: **HIGH**.

D4. **Encryption-at-rest claim.** Spec claims data is encrypted at rest; diff stores in cleartext or with reversible encoding (base64). Default severity: **HIGH**.

## E. Sensitive data exposure (OWASP A02 + A04:2021)

E1. **PII in logs.** Logger calls that include email/phone/SSN/full-name/auth-tokens in their formatted output. Default severity: **HIGH**.

E2. **Verbose errors to client.** Stack traces, SQL error text, internal paths returned in HTTP responses. Default severity: **MEDIUM**.

E3. **Hardcoded sensitive data.** Production hostnames, internal IPs, customer IDs, real names committed in code or fixtures. Default severity: **MEDIUM**.

E4. **Cache control on sensitive endpoints.** Endpoints returning user data missing `Cache-Control: private, no-store`. Default severity: **MEDIUM**.

## F. SSRF / dangerous outbound (OWASP A10:2021)

F1. **URL fetch with user input.** New code does an outbound HTTP fetch where the host or path is user-controlled, without an allowlist. Default severity: **CRITICAL**.

F2. **Redirect with user input.** Open-redirect via unvalidated `next=` / `return_url=` parameter. Default severity: **HIGH**.

F3. **DNS rebinding window.** A pre-flight check resolves a host but the actual request re-resolves; or `localhost`/`169.254.169.254` not blocklisted on a fetcher. Default severity: **HIGH**.

## G. Deserialisation & file handling (OWASP A08:2021)

G1. **Unsafe deserialisation.** `pickle.loads`, `yaml.load` (without `SafeLoader`), `Marshal.load`, `ObjectInputStream` over user-controlled bytes. Default severity: **CRITICAL**.

G2. **Path traversal.** File paths constructed from user input without `os.path.realpath` + base-prefix check, or equivalent. Default severity: **CRITICAL**.

G3. **Unrestricted file upload.** New upload handler does not check MIME, extension, magic bytes, and storage path; or stores under web-served root. Default severity: **HIGH**.

G4. **Zip/tar slip.** Archive extraction without sanitising entry names against `..`. Default severity: **HIGH**.

## H. Misconfiguration (OWASP A05:2021)

H1. **Permissive CORS.** `Access-Control-Allow-Origin: *` paired with credentials, or reflected origin without an allowlist. Default severity: **HIGH**.

H2. **Security headers missing.** New HTML response without `Content-Security-Policy`, `X-Frame-Options`/`frame-ancestors`, `X-Content-Type-Options: nosniff`. Default severity: **MEDIUM**.

H3. **Default credentials / admin panel.** Spec-required default password not forced-rotated; admin path reachable without authentication wall. Default severity: **CRITICAL**.

H4. **Cloud IAM.** New Terraform / CloudFormation grants `*:*` or `s3:*`/`iam:PassRole` without scoping. Default severity: **HIGH**.

## I. Logging & monitoring (OWASP A09:2021)

I1. **Auth events not logged.** Login success/failure, role change, password change, token issuance — none recorded. Default severity: **MEDIUM**.

I2. **Logs writable by attacker.** A user-controlled path is appended without escaping (log injection / forged events). Default severity: **MEDIUM**.

I3. **Tamper detection.** Audit log written without append-only / signed-chain semantics where the threat-model demands it. Default severity: **MEDIUM**.

## J. LLM / agent / MCP-specific (panel-named gap)

J1. **Prompt injection.** User-controlled text reaches a system-or-tool prompt position; the threat-model treats it as untrusted. Default severity: **HIGH**.

J2. **Tool exfiltration.** New tool/MCP server granted `Read` or `WebFetch` against paths/hosts that contain secrets (`.env`, AWS metadata service, `~/.ssh/`). Default severity: **CRITICAL**.

J3. **Sub-agent spawning without budget guard.** A new code path spawns `claude -p` directly, bypassing `safe-spawn-claude.sh`. Default severity: **HIGH**. [Source: user CLAUDE.md "Sub-agent spawn — PHẢI qua safe-spawn-claude.sh"]

J4. **Hook bypass.** Code path edits files via a non-`Edit` tool to circumvent `pre-edit-stash.sh` or `lint-touched.sh`. Default severity: **MEDIUM**.

J5. **Identity assertion.** A multi-agent message is accepted without verifying the sender (no mTLS, no signed token, no checksum). Default severity: **HIGH**.

## K. Supply chain (OWASP A06:2021 + recurring panel finding)

K1. **New dependency without provenance.** Diff adds a package with no version pin, no integrity hash (`requirements.txt`/`package-lock.json`/`go.sum` not updated), or from a non-canonical registry. Default severity: **HIGH**.

K2. **Typosquat / namespace-confusion candidate.** New dep name resembles a popular package (`requets`, `lodash-extra-utils`). Default severity: **MEDIUM** (HIGH if no maintainers / <100 weekly downloads).

K3. **Postinstall scripts.** New dep runs arbitrary code on install (`npm` postinstall, `setup.py` `cmdclass`). Default severity: **HIGH**.

K4. **Pinned to mutable tag.** Dockerfile `FROM image:latest` or git submodule on a branch instead of a SHA. Default severity: **MEDIUM**.

## L. Secrets handling (recurring panel finding)

L1. **`.env` committed.** New `.env*` file at any path. Default severity: **CRITICAL**.

L2. **Secret in CI yaml.** Plaintext token in `.github/workflows/*` or equivalent. Default severity: **CRITICAL**.

L3. **Secret in logs / errors.** Format string embeds `os.environ['*_KEY']` or similar. Default severity: **HIGH**.

L4. **Leaked secret rotation.** Diff adds a new secret value into the repo without an accompanying rotation note in `decisions.md`. Default severity: **HIGH**.

## M. Test coverage on security boundaries

M1. **Auth-decorated endpoint without auth test.** New `@require_auth` (or equivalent) handler ships without at least one test asserting the unauthenticated path returns 401/403. Default severity: **MEDIUM**.

M2. **Validator without negative test.** Input validator added without a test asserting the invalid case is rejected. Default severity: **MEDIUM**.

M3. **Crypto helper without known-answer test.** New encryption/signing helper without a KAT test (encrypt-then-decrypt round-trip, fixed-vector check). Default severity: **MEDIUM**.

---

End of security checklist. After completion, proceed to PE checklist if `--dim` includes `pe`.
