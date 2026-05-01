# Rollback Guide for CQR-A Model Routing Fragment

## The 4 things that change after install

1. **Sub-agent model recommendations change.** When you ask Claude to spawn a sub-agent
   or when it drafts a `safe-spawn-claude.sh` command, it will now recommend Haiku or
   Sonnet for trivial/small/feature tasks instead of always defaulting to Opus. This is
   the intended behavior. If a sub-agent produces bad output, the escalation triggers
   (test failure, diff size, keyword fence) will upgrade it — but that upgrade requires
   at least one iteration on the cheaper model first.

2. **A new `## Model Routing` section appears in CLAUDE.md.** This section is read by
   the model at every session start. It consumes a small amount of the system context
   window (~40 lines). If you are working near context limits this has marginal cost.

3. **Fansipan, auth, security, billing, migrations paths remain Opus-locked.** The
   fragment explicitly re-states the FANSIPAN ABSOLUTE RULE and path locks. No change
   in practice — these tasks ran on Opus before and still will.

4. **Browse-heavy long-context work is redirected to `claude-opus-4-6`.** If you
   initiate work with >50K tokens of context AND web-fetch tools, the fragment
   recommends pinning `claude-opus-4-6` instead of `claude-opus-4-7`. Opus 4.7 has a
   documented -4.4pp BrowseComp regression. This is the only case where 4.6 is
   preferred over 4.7.

## The env var kill switch (fastest rollback, no file edit)

```bash
export CLAUDE_PIN_MODEL=claude-opus-4-7
```

Add to `~/.bashrc` or `~/.zshrc` for permanent effect. This overrides every routing
decision — all sub-agents will use Opus regardless of task class. The fragment stays
installed but is effectively inert.

To re-enable routing after a pin:

```bash
unset CLAUDE_PIN_MODEL
# or remove the export line from your shell profile
```

## The delete-the-block rollback (clean removal)

Remove the entire `## Model Routing` section from `~/.claude/CLAUDE.md`:

```bash
# Backup first
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak-$(date +%Y%m%d)

# Remove from CQR-A comment through CQR-A END comment (sed approach)
sed '/<!-- CQR-A FRAGMENT/,/CQR-A END ====/{/CQR-A END ====/{N;d};d}' \
  ~/.claude/CLAUDE.md > /tmp/claude_clean.md && mv /tmp/claude_clean.md ~/.claude/CLAUDE.md
```

Or do it manually: open `~/.claude/CLAUDE.md`, find the `<!-- CQR-A FRAGMENT` comment,
delete from that line through the `<!-- CQR-A END` closing comment (inclusive), and
save. The result should be that `## Neural-Memory Recall First` follows directly after
the `## SDLC Agent Routing` section's Exceptions list.

## Restore from backup

```bash
cp ~/.claude/CLAUDE.md.bak-YYYYMMDD ~/.claude/CLAUDE.md
```

## When to escalate

Contact the user (file an issue or note in routing-misses.md) rather than rolling back:

- Quality misses >2/week sustained for 2+ weeks on a stable task class
- Monthly spend reduction <10% after 60 days despite no Fansipan-heavy weeks
- A sub-agent consistently refuses or produces empty output on a class it should handle
- The BrowseComp Opus 4.6 recommendation causes problems after an Anthropic model update
