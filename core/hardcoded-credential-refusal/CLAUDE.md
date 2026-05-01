# hardcoded-credential-refusal — agent-facing fragment

When the credential-scan hook refuses an edit, do NOT auto-bypass by adding a `gitleaks:allow` marker. Surface the refusal to the operator:

> The credential-scan hook refused this edit because it appears to contain a credential pattern (`<pattern_name>`).
>
> If this is a legitimate test fixture or example, add `// gitleaks:allow` on the same line or within ±3 lines of the credential.
>
> If this is a real credential that needs to land in a file, the file should be in `.gitignore` and the credential should come from an env var or secret manager — not committed source code.

Auto-rolling a `gitleaks:allow` marker through agent code defeats the human-in-the-loop check the gate exists to enforce.

## Why deterministic > heuristic here

The agent itself cannot reliably distinguish a "real credential the user accidentally pasted into context" from a "fake credential for a test fixture." The hook errs on the refuse side; the operator decides. Charter §2.1 anti-fantasy: refuse-and-ask beats guess-and-commit.

End of `core/hardcoded-credential-refusal/CLAUDE.md`.
