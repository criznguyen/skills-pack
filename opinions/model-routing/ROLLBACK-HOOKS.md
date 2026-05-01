# CQR-C Hooks — Rollback & Disable

The CQR-C hook subsystem fail-safes by default: every script exits 0 even on internal error, so a misbehaving hook degrades routing to "always Opus" without breaking Claude Code. Three escalating-force rollback options are documented here.

> Companion file: this is the CQR-C (hooks) rollback. The CQR-A (CLAUDE.md fragment) rollback lives in `ROLLBACK.md` in the same directory.

---

## Level 1 — Per-event disable (least invasive)

Comment out a single problematic hook in `~/.claude/settings.json` by removing its entry from the corresponding event array. Example: disable just the `diff-size-tripwire`:

```bash
jq '.hooks.PostToolUse |= map(
    .hooks |= map(select(.command != "~/.claude/hooks/cqr/diff-size-tripwire.sh"))
    | select(.hooks | length > 0)
)' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

The other 4 hooks continue to run.

Mapping of hook → settings.json path:

| Hook | settings.json key | matchers |
|------|-------------------|----------|
| `user-prompt-submit.sh`    | `.hooks.UserPromptSubmit` | `""` |
| `lock-opus.sh`             | `.hooks.PreToolUse`       | `Edit\|Write\|MultiEdit\|NotebookEdit`, `Bash` |
| `post-tool-use-failure.sh` | `.hooks.PostToolUse`      | `Bash\|Edit\|Write\|MultiEdit` |
| `diff-size-tripwire.sh`    | `.hooks.PostToolUse`      | `Edit\|Write\|MultiEdit` |
| `subagent-stop.sh`         | `.hooks.SubagentStop`     | `""` |

After editing, validate:

```bash
jq empty ~/.claude/settings.json && echo "settings.json valid"
```

Restart Claude Code (close + reopen the session) for changes to take effect.

---

## Level 2 — Whole-subsystem disable (keeps scripts on disk)

Move all CQR-C hook entries out of settings.json in one operation:

```bash
SETTINGS=~/.claude/settings.json
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"

jq '
  .hooks //= {}
  | .hooks |= (
      to_entries | map(
          .value |= map(
              .hooks |= map(select(
                  (.command // "") | test("/\\.claude/hooks/cqr/") | not
              ))
          )
          | .value |= map(select(.hooks | length > 0))
      )
      | map(select(.value | length > 0))
      | from_entries
  )
' "$SETTINGS" > /tmp/s.json && mv /tmp/s.json "$SETTINGS"

jq empty "$SETTINGS" && echo "all CQR-C entries removed; settings.json valid"
```

The hook scripts themselves remain in `~/.claude/hooks/cqr/`. Re-enable later by re-running the merge step in `INSTALL-HOOKS.md` §3.

---

## Level 3 — Nuclear: pin Opus and uninstall

Restore the always-Opus baseline immediately (no settings.json edit required):

```bash
export CLAUDE_PIN_MODEL=claude-opus-4-7
echo 'export CLAUDE_PIN_MODEL=claude-opus-4-7' >> ~/.bashrc   # persist
```

`user-prompt-submit.sh` checks `$CLAUDE_PIN_MODEL` first and emits a session-pin hint that overrides every other rule. The agent reads it and applies it to all sub-agent spawns. (This is the same kill switch documented in §8.4 of the FINAL design.)

Then, optionally remove everything:

```bash
# (after Level 2 settings.json cleanup)
rm -rf ~/.claude/hooks/cqr
rm -f  ~/.claude/cqr-locks.txt
rm -f  ~/.claude/cqr-hooks.log ~/.claude/cqr-hooks.log.*
rm -f  ~/.claude/state/lock-opus.flag \
       ~/.claude/state/escalate-next-*.flag \
       ~/.claude/state/tripwire-*.txt \
       ~/.claude/state/lock.log \
       ~/.claude/state/diff-size.log \
       ~/.claude/state/subagent-debrief.log
```

---

## Diagnosing misfires before disabling

If you see unexpected routing hints, before rolling back check:

```bash
# 1. Recent advisories
tail -50 ~/.claude/cqr-hooks.log

# 2. Sticky flags that should have cleared but didn't
ls -la ~/.claude/state/

# 3. Verify the locks file isn't surprising you
cat ~/.claude/cqr-locks.txt 2>/dev/null
```

Common surprises:

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Every prompt locked to Opus | A keyword like `audit` or `migration` matched something benign | Edit `~/.claude/cqr-locks.txt` to drop or narrow the keyword |
| Tripwire stays escalated across sessions | Stale `tripwire-<id>.txt` from a crashed session | `rm ~/.claude/state/tripwire-*.txt` |
| `lock-opus.flag` never clears | `user-prompt-submit.sh` clears it on next turn — if you haven't sent a turn since, that's expected | Send any prompt; the flag clears |
| Hooks not firing at all | Hook scripts not executable, or jq missing | `chmod +x ~/.claude/hooks/cqr/*.sh && command -v jq` |
| `additionalContext` appears but agent ignores it | Hooks ADVISE — they cannot force a switch | Use the Level 3 kill switch (`CLAUDE_PIN_MODEL`) when certainty is required |
| Hook prints JSON but you can't see it in Claude Code | Hooks emit to stdout, parsed by Claude Code internally — check `~/.claude/cqr-hooks.log` for the advisory text |

---

## Recovery from a corrupted settings.json

The merge command in `INSTALL-HOOKS.md` §3 makes a timestamped backup. If something went wrong:

```bash
ls -t ~/.claude/settings.json.bak.* | head -1   # most recent backup
cp $(ls -t ~/.claude/settings.json.bak.* | head -1) ~/.claude/settings.json
```

If no backup exists, paste a minimal stub:

```json
{
  "hooks": {}
}
```

Claude Code will start with no hooks active. You can then reinstall.

---

## When to keep the hooks but tune (not rollback)

| Scenario | Action |
|----------|--------|
| One specific keyword over-fires (e.g. `migration` matches innocent docs) | Drop that line from `~/.claude/cqr-locks.txt` |
| Diff-size threshold of 150 LOC too aggressive on Write-from-template | `export CQR_DIFF_THRESHOLD=300` in `~/.bashrc` |
| Tripwire escalates too eagerly | `export CQR_TRIPWIRE_THRESHOLD=3` (default 2) |
| You want a different state dir | `export CQR_STATE_DIR=$HOME/.claude/cqr-state` |
| You want hooks to load a different lock list | `export CQR_LOCKS_FILE=$HOME/cqr-custom.txt` |
| You want hooks silent (no log file) | `export CQR_LOG_FILE=/dev/null` |

These knobs make rollback rarely necessary.
