# quarantine-pack — operator-facing convention prose


This file performs NO runtime check — documentation only.

## 1. Reading the telemetry

The hook appends one JSONL line per matched tool call to `~/.claude/telemetry.jsonl` (the same file `telemetry.sh` and `postcondition-hook.sh` write). Inspect tagged events from the current session with:

```bash
jq 'select(.event=="quarantine" and .matcher_status=="tagged")' \
  ~/.claude/telemetry.jsonl | tail -50
```

Other useful filters:

```bash
# Skipped (trusted MCP) calls:
jq 'select(.event=="quarantine" and .matcher_status=="skipped")' ~/.claude/telemetry.jsonl

# WebFetch surface only:
jq 'select(.event=="quarantine" and .surface=="web_fetch")' ~/.claude/telemetry.jsonl

# Per-session p50 latency:
jq -r 'select(.event=="quarantine") | .latency_ms' ~/.claude/telemetry.jsonl \
  | sort -n | awk 'BEGIN{c=0} {a[c++]=$1} END{print a[int(c/2)] " ms (n="c")"}'
```

The privacy invariant (AC6) holds: the JSONL never contains `tool_input` or `tool_response` bodies. Only `tool_name`, `surface` kind, `matcher_status`, `trusted_mcp` namespace, latency, and session id are persisted. Mirrors `telemetry.sh` line 11 invariant.

## 2. Trusted-MCP allowlist edits

The default allowlist (`~/.claude/quarantine.d/trusted-mcp-allowlist.txt`) ships six entries — see `README.md` "Trusted-MCP allowlist" for the per-entry rationale. Operators extend the file directly:

```bash
echo 'mcp__internal_wiki' >> ~/.claude/quarantine.d/trusted-mcp-allowlist.txt
```

The hook reads the file on every invocation (no daemon, no cache); the next `mcp__internal_wiki_*` tool call will emit `matcher_status=skipped trusted_mcp=mcp__internal_wiki` instead of `tagged`.

**In this repo (claude-skills) every allowlist edit requires** a `decisions.md` D3 trail and a `## Trusted-MCP Justification` PR-body section. CI step `trusted-mcp-allowlist-justify-check` warns on PRs that diff-touch `core/quarantine-pack/templates/trusted-mcp-allowlist.txt` without the body section. The `system-change:` audit checklist for `core/quarantine-pack/templates/` includes "every new line is justified in the PR body and decisions.md D3" — auditor may BLOCK on missing justification (TM7).

Operator-local additions (in your own clone) are advisory; the CI step only fires when this repo's templates/ file diff-touches.

## 3. Forbidden content in hooks/*.sh (TM4 / NG6)

NO LLM invocation. NO sub-agent spawn. The canonical forbidden literal list — each enforced by `core/quarantine-pack/tests/test-no-claude-spawn.sh` regex:

- **`claude -p`** — direct CLI spawn
- **`Agent(`** — Anthropic SDK Agent tool
- **`anthropic.`** — Anthropic Python/JS SDK call
- **`@anthropic`** — Anthropic SDK package import

Hooks are deterministic shell ONLY (`bash` + `jq` + `python3` fallback + `sed` + `grep`); semantic verification is the audit sub-agent's job (charter §2.3 independence-of-reviewer). The `system-change:` audit checklist for any change to `core/quarantine-pack/hooks/` re-runs the literal grep. CI step `quarantine-hook-integrity-check` re-runs it on every push.

## 4. `<UNTRUSTED>` discipline (developer onboarding only)

The `<UNTRUSTED>...</UNTRUSTED>` framing of tool output is a *prompt-hygiene pedagogy* device for skill authors — it lives in `README.md` "<UNTRUSTED> discipline" only. It is NOT charter-grade enforcement: adversarial close-tag spoofing defeats the marker as a structural defense per F2-6 / F4-4. Charter §2.2 sub-clause #2 prose explicitly disclaims it. CI step `quarantine-charter-untrusted-leak-check` greps `docs/synthesis/**/*.md` for the literal token outside backtick-fenced spans and rejects accidental promotion of the prompt-pattern to charter prose.

## 5. Uninstall

Three commands (mirrors README "Uninstall"):

```bash
bash core/governance-pack/uninstall.sh                       # removes hook + de-registers from settings.json
bash core/governance-pack/uninstall.sh --quarantine-purge    # also removes ~/.claude/quarantine.{d,json}
git revert <quarantine-pack commit SHA>                       # restores charter §2.2 prose and removes the skill
```

Operator-owned data (the trusted-MCP allowlist) is preserved across non-purge uninstalls.

End of `core/quarantine-pack/CLAUDE.md`.
