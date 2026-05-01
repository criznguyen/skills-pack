# sandbox-default-on — agent-facing fragment

When the operator runs `governance-pack/install.sh --enable-sandbox`, every subsequent session starts in `defaultMode: "sandbox"`. As an agent inside that session you will see permission errors on:

- Network egress (the sandbox blocks outbound TCP except to allowlisted hosts).
- File writes outside the working tree.
- Process spawning that escapes the sandbox.

Those errors are not bugs in your skill code; the sandbox is doing its job. Surface the error to the operator with the rollback recipe (`docs/conventions/sandbox-rollback.md` if reachable, else cite `core/sandbox-default-on/templates/sandbox-rollback.md`). Do NOT auto-rollback.

If your skill REQUIRES sandbox-break behavior (pip install, native build, package fetch), declare `sandbox_required: false` in your SKILL.md frontmatter. The audit checklist verifies the claim.

End of `core/sandbox-default-on/CLAUDE.md`.
