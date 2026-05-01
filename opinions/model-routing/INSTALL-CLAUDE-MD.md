# Installing CLAUDE.md.fragment into ~/.claude/CLAUDE.md

## What this does

Appends the `## Model Routing` block to your global CLAUDE.md. The block tells Claude
which model to use when spawning sub-agents or starting a focused session. It adds
permission to downshift for task classes not covered by the existing SDLC routing block.

It does NOT modify any existing rules. It adds a new `##` section between the existing
`## SDLC Agent Routing` section and `## Neural-Memory Recall First`.

## Exact insertion point

Current file: `~/.claude/CLAUDE.md`

```
Line 84: - Emergency triage when a sub-agent is blocking user workflow and the action is small + reversible
Line 85: (blank)
                                        <--- INSERT HERE
Line 86: ## Neural-Memory Recall First (CRITICAL)
```

The fragment block lands on line 86, pushing `## Neural-Memory Recall First` and
everything after it down by 49 lines.

## Install command (one-liner)

```bash
# Backup first (mandatory)
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak-$(date +%Y%m%d)

# Find the insertion line and insert
LINE=$(grep -n '^## Neural-Memory Recall First' ~/.claude/CLAUDE.md | cut -d: -f1)
head -n $((LINE - 1)) ~/.claude/CLAUDE.md > /tmp/claude_new.md
cat /home/criznguyen/projects/claude-skills/opinions/model-routing/CLAUDE.md.fragment >> /tmp/claude_new.md
echo "" >> /tmp/claude_new.md
tail -n +${LINE} ~/.claude/CLAUDE.md >> /tmp/claude_new.md
mv /tmp/claude_new.md ~/.claude/CLAUDE.md
```

## Manual install (if you prefer to eyeball it)

1. Open `~/.claude/CLAUDE.md` in your editor.
2. Find this exact line (currently line 84):
   ```
   - Emergency triage when a sub-agent is blocking user workflow and the action is small + reversible
   ```
3. Place your cursor at the end of the blank line immediately after it (line 85).
4. Paste the entire contents of `CLAUDE.md.fragment`.
5. Ensure there is one blank line between the fragment's `CQR-A END` comment and
   `## Neural-Memory Recall First`.

## Verify the install

After installing, ask Claude Code:

> What model should I use to rename a function in utils.ts?

Expected: Claude recommends `claude-haiku-4-5` (trivial class, single-file rename).

> What model should I use for a security audit of the auth module?

Expected: Claude recommends `claude-opus-4-7` with reason `keyword-fence` or `path-fence`.

> What model for a 3-file feature with new tests?

Expected: Claude recommends `claude-sonnet-4-6` (feature class, 3 files).

## What changes after install

See ROLLBACK.md for the full list of behavioral changes.

## Rollback

See ROLLBACK.md.
