# Example 05 — `audit`: PCI-DSS compliance review

## Input

```yaml
prompt: |
  audit the payment flow for PCI-DSS compliance gaps. Read-only
  with findings ranked CRITICAL/HIGH/MEDIUM/LOW/INFO.
files_in_scope:
  - "src/payments/checkout.ts"
  - "src/payments/webhook.ts"
  - "src/payments/refund.ts"
tool_plan: ["Read", "Grep", "Write"]
loc_hint: null
```

## Reasoning trace


(Rungs 2-6 not consulted — though `audit` and `compliance` keywords would also fire if we continued.)

## Output

```json
{
  "class": "audit",
  "signals_used": ["path"],
  "files_in_scope": 3,
  "loc_estimate": null,
  "tie_break_applied": false
}
```

## Downstream

`model-router` sees `class: "audit"`. The `audit` and `compliance` keywords also fire the keyword fence at Step 1. Either way → `claude-opus-4-7`, LOCKED.

## Why audit is terminal

A 3-file audit could otherwise classify as `feature` on file-count alone. Audits are read-only deliverables — the file count is misleading. We hard-set `audit` and stop. Per FANSIPAN-style logic: cost savings on a single audit sub-agent (≈$0.30) are dwarfed by the cost of one missed CRITICAL finding (R1 §3 SWE-bench Pro 20pp gap on hardest tasks).
