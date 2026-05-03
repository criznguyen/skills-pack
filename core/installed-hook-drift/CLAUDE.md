# installed-hook-drift — agent-facing fragment

If you see drift findings on stdout from `core/installed-hook-drift/hooks/check-drift.sh`, do NOT auto-overwrite the installed hooks. The operator may have legitimate local edits.

The correct surface:

> The installed-hook-drift reporter found N drift findings:
> - `~/.claude/hooks/<group>/<hook>.sh` differs from `<repo>/core/<group>/hooks/<hook>.sh` (sha256 mismatch).
>
> This means the installed copy was modified since `governance-pack/install.sh` last ran. The operator can either:
> 1. Re-run `bash core/governance-pack/install.sh` to overwrite the installed copy with the canonical version (loses local edits).
> 2. Carry the local edit forward into the canonical version via PR.
>
> Which one applies?

If you see `orphan` findings, those are installed hooks under `~/.claude/hooks/<group>/` where `<group>` does not correspond to any `core/<group>/` skill in the current repo. Those are not necessarily wrong — they may be operator-custom hooks. Surface and ask.

End of `core/installed-hook-drift/CLAUDE.md`.
