# `hardcoded-credential-refusal` — PreToolUse hook refusing credential writes

v2.0 P1 #2. Charter §2.2 hooks-over-rules. Regex bank derived from gitleaks (MIT).

## What it ships

| File | Purpose |
|---|---|
| `SKILL.md` | Skill body. |
| `CLAUDE.md` | Agent-facing fragment. |
| `hooks/credential-scan.sh` | PreToolUse(`Edit\|Write\|MultiEdit`). Scans new content; refuses on match unless `gitleaks:allow` marker within ±3 lines. |
| `templates/credential-regex-bank.txt` | 8+ pattern bank. Hand-editable. |
| `tests/test-credential-scan.sh` | 9-case unit suite (one per pattern + marker bypass + AWS example exemption). |
| `tests/test-no-claude-spawn.sh` | TM4 grep mirror. |
| `examples/sample-output.jsonl` | privacy-clean. |

## Pattern bank

| Name | Regex |
|---|---|
| `aws_access_key` | `AKIA[0-9A-Z]{16}` |
| `github_pat` | `gh[ps]_[A-Za-z0-9]{36}` |
| `stripe_live` | `sk_live_[0-9A-Za-z]{24}` |
| `openai_key` | `sk-[A-Za-z0-9]{48}` |
| `slack_bot` | `xoxb-[A-Za-z0-9-]+` |
| `jwt` | `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` |
| `rsa_private_key` | `-----BEGIN RSA PRIVATE KEY-----` |
| `high_entropy_hex` | `[a-f0-9]{40,}` |

The official AWS-docs example (`AKIAIOSFODNN7EXAMPLE`) is auto-exempted regardless of marker.

## Install

```bash
bash core/governance-pack/install.sh        # Step 12 wires hardcoded-credential-refusal
```

The installer:
1. Copies `hooks/credential-scan.sh` to `~/.claude/hooks/hardcoded-credential-refusal/`.
2. Seeds `~/.claude/hardcoded-credential-refusal/credential-regex-bank.txt` from the template.
3. Registers the `PreToolUse(Edit|Write|MultiEdit)` matcher in `~/.claude/settings.json`.

## Uninstall

```bash
bash core/governance-pack/uninstall.sh
rm -rf ~/.claude/hardcoded-credential-refusal
```

## Performance budget

| Metric | Target |
|---|---|
| Median per-call latency | ≤ 10 ms (8 regex passes) |
| Hard timeout | 5000 ms |

## References

- gitleaks: <https://github.com/gitleaks/gitleaks> (MIT)
