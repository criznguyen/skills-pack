# Example 02 — keyword fence (`audit`) hard-locks Opus 4.7

## Input

```yaml
prompt: "spawn a sub-agent to audit the payment flow for PCI-DSS compliance gaps"
cwd: "/home/criznguyen/projects/some-saas"
files_in_scope: ["src/payments/checkout.ts", "src/payments/webhook.ts"]
subagent_type: "Compliance Auditor"
tool_plan: ["Read", "Grep"]
context_utilization_pct: 12
env.CLAUDE_PIN_MODEL: unset
```

## Reasoning trace

1. **Step 1 — keyword fence**: prompt contains `audit` AND `compliance` AND `pci-dss` (matches `compliance` keyword). Two fences would fire; we stop on the first match (Step 1 sub-step 4).
   - Also: `subagent_type: "Compliance Auditor"` would fire role-fence.
   - Primary reason: `keyword-fence` (Step 1 evaluates keyword before role in our priority order, but role-fence would also lock to Opus). Either way → Opus 4.7.
2. **Steps 2-7 skipped** (Step 1 short-circuits).

## Output

```json
{
  "model": "claude-opus-4-7",
  "class": "audit",
  "confidence": 0.95,
  "reason": "keyword-fence",
  "escalation_triggers_seen": [],
  "fence_hit": "audit"
}
```

## Why this matters

R1 §3 — SWE-bench Pro gap between Opus 4.7 and Sonnet 4.5 widens to ~20pp on the hardest tasks. Compliance audits are exactly that population. Cost savings on a single sub-agent (≈$0.15) are dwarfed by the cost of one missed CRITICAL finding.

## How the caller applies it

```bash
/home/criznguyen/bin/safe-spawn-claude.sh /tmp/agent-pci-audit.md \
  claude-opus-4-7 pci-audit
```
