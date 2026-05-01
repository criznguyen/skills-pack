---
name: hardcoded-credential-refusal
description: PreToolUse hook (matcher Edit|Write|MultiEdit) refusing writes that introduce high-entropy credential patterns (AWS access key, GitHub PAT, Stripe sk_live, OpenAI sk-, Slack xoxb-, JWT, RSA private-key blocks, generic high-entropy strings) without a `// gitleaks:allow` marker comment within ±3 lines. Hard-block exit 2 with stderr advisory. Regex bank derived from gitleaks (MIT). v2.0 P1 #2.
type: governance
tools: Edit, Write, MultiEdit
model: opus
blast_radius: local-write
last-validated: 2026-04-29
---

# hardcoded-credential-refusal

Charter §2.2 hooks-over-rules. Per-skill prose telling the agent *"don't write keys"* is unreliable; an instruction-injected agent will write them. A `PreToolUse(Edit|Write|MultiEdit)` hook scanning `tool_input.new_string` / `tool_input.content` against a gitleaks-derived regex bank is the deterministic enforcement.

## When to use

Auto-installed by `core/governance-pack/install.sh` Step 12. Operators with shell access to a git working tree are protected against writes containing:

- AWS access key (`AKIA[0-9A-Z]{16}`)
- GitHub PAT (`gh[ps]_[0-9A-Za-z]{36}`)
- Stripe live secret (`sk_live_[0-9A-Za-z]{24}`)
- OpenAI API key (`sk-[0-9A-Za-z]{48}`)
- Slack bot token (`xoxb-[0-9A-Za-z-]+`)
- JWT (`eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`)
- RSA private-key blocks (`-----BEGIN RSA PRIVATE KEY-----`)
- Generic high-entropy hex (`[a-f0-9]{40,}` 40+ char hex)

Full pattern bank lives in `templates/credential-regex-bank.txt`; operator-editable.

## When NOT to use

- **For test fixtures using the official AWS example credential** (`AKIAIOSFODNN7EXAMPLE`). The hook honors a `// gitleaks:allow` marker comment within ±3 lines, AND treats the literal AWS-documented example pattern as auto-allow.
- **For documentation that documents the regex itself.** This SKILL.md, the `templates/credential-regex-bank.txt`, and CI grep test fixtures are exempted via path-based suppression.

## Bypass: `gitleaks:allow` marker comment

Add a same-line or nearby (`±3 lines`) comment matching the literal `gitleaks:allow`:

```js
// gitleaks:allow — test fixture for credential-detector unit tests
const FAKE_AWS_KEY = "AKIAIOSFODNN7EXAMPLE";
```

The hook honors `gitleaks:allow` because it's the upstream gitleaks idiom; operators already familiar with gitleaks will recognise the marker.

## Per-session disable

```bash
export HARDCODED_CREDENTIAL_REFUSAL_DISABLE=1
```

## Forbidden in hook bodies (TM4)

`hooks/credential-scan.sh` is shell + grep + jq + python3-fallback only. Enforced by `tests/test-no-claude-spawn.sh`.

## Telemetry

```json
{"event":"credential-scan","ts":"...","tool":"Edit","decision":"refused|pass|bypass","matched_pattern":"aws_access_key","file_path":"...","session_id":"..."}
```

Privacy invariant: the matched substring itself is NEVER persisted, only the pattern *name* (`aws_access_key`, `github_pat`, etc.). The credential is what we are refusing — logging it would defeat the point.

## Install / Uninstall

Wired by `core/governance-pack/install.sh` Step 12. Three-command uninstall:

```bash
bash core/governance-pack/uninstall.sh   # removes hook + de-registers
rm -rf ~/.claude/hardcoded-credential-refusal
```

## References

- gitleaks (MIT): <https://github.com/gitleaks/gitleaks>
- Charter §2.2 hooks-over-rules: [`docs/synthesis/v1.1/charter-v1.1.md`](../../docs/synthesis/v1.1/charter-v1.1.md)
