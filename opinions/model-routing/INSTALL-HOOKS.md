# CQR-C Hooks — Install & Verify

Cost-Quality-Routing Component-C: hook layer that **advises** the agent on which Claude model to use, based on prompt content, file paths, destructive commands, repeated tool failures, sub-agent refusals, and diff size. Hooks NEVER switch the model directly — Claude Code does not expose that lever — but every hook injects an `additionalContext` hint that the agent reads before its next decision.

Companion to:
- `opinions/model-routing/skills/model-router/` (the structured-output recommender)
- `~/.claude/CLAUDE.md` `## Model Routing` block (the human-readable rubric)
- `/home/criznguyen/bin/safe-spawn-claude.sh` (the CLI wrapper that applies `--model`)

---

## 0. Prerequisites

- `bash` ≥ 4
- `jq` (used by every hook to parse stdin JSON and emit JSON output)
- Claude Code with hooks support (any 2025+ build)
- `~/.claude/` directory exists (Claude Code creates it on first run)

Quick check:

```bash
command -v jq >/dev/null && echo "jq ok" || echo "INSTALL: sudo apt-get install jq"
ls -d ~/.claude && echo "claude dir ok"
```

If `jq` is missing the hooks fail-safe (exit 0, log a warning to stderr) — but routing degrades to "always Opus", so you lose the savings. Install it.

---

## 1. Install the hook scripts

```bash
# 1a. Create the per-namespace hook directory
mkdir -p ~/.claude/hooks/cqr ~/.claude/state

# 1b. Copy the five scripts
SRC=/home/criznguyen/projects/claude-skills/opinions/model-routing/hooks
cp "$SRC"/user-prompt-submit.sh   ~/.claude/hooks/cqr/
cp "$SRC"/lock-opus.sh             ~/.claude/hooks/cqr/
cp "$SRC"/post-tool-use-failure.sh ~/.claude/hooks/cqr/
cp "$SRC"/subagent-stop.sh         ~/.claude/hooks/cqr/
cp "$SRC"/diff-size-tripwire.sh    ~/.claude/hooks/cqr/

# 1c. Make them executable
chmod +x ~/.claude/hooks/cqr/*.sh
```

Verify all 5 scripts pass `bash -n`:

```bash
for f in ~/.claude/hooks/cqr/*.sh; do
  bash -n "$f" && echo "syntax ok: $(basename "$f")"
done
```

Expected output: 5 lines reading `syntax ok: ...`.

---

## 2. (Optional) Install the lock list

The hooks have built-in defaults for keyword/path/bash patterns. If you want to override them — for example to add `**/payments/**` to the path fence — copy the example file and edit:

```bash
cp /home/criznguyen/projects/claude-skills/opinions/model-routing/cqr-locks.example.txt \
   ~/.claude/cqr-locks.txt
$EDITOR ~/.claude/cqr-locks.txt
```

Format is documented inside the file (one `keyword:`, `path:`, or `bash:` line per rule). The hooks load this file lazily on every fire — no restart needed.

---

## 3. Wire the hooks into `settings.json`

The fragment is at `opinions/model-routing/settings.json.fragment`.

**If your `~/.claude/settings.json` does not yet have a `hooks` key**, just paste the entire `hooks: { ... }` block from the fragment in.

**If you already have a `hooks` key** (e.g. from disler/claude-code-hooks-mastery), you must merge per-event arrays. Each top-level key (`UserPromptSubmit`, `PreToolUse`, etc.) is an array of matcher groups — append the fragment's entries to the existing arrays. Do not overwrite, or you'll lose your prior hooks.

A safe merge (when both files are valid JSON) using `jq`:

```bash
SETTINGS=~/.claude/settings.json
FRAG=/home/criznguyen/projects/claude-skills/opinions/model-routing/settings.json.fragment
# Strip the comment field from the fragment before merging
jq 'del(._comment_cqr)' "$FRAG" > /tmp/cqr-frag.json

# Backup
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"

# Merge: existing settings + fragment hooks (concatenates arrays per event)
jq -s '
  .[0] as $a | .[1] as $b
  | $a
  | .hooks = (
      ($a.hooks // {}) as $ah
      | ($b.hooks // {}) as $bh
      | reduce ($ah + $bh | keys_unsorted | unique[]) as $k
        ({}; .[$k] = (($ah[$k] // []) + ($bh[$k] // []) | unique))
    )
' "$SETTINGS" /tmp/cqr-frag.json > /tmp/settings.merged.json

# Validate then install
jq empty /tmp/settings.merged.json && mv /tmp/settings.merged.json "$SETTINGS"
```

Sanity-check by `cat ~/.claude/settings.json | jq '.hooks | keys'` — expected output includes `["PostToolUse","PreToolUse","SubagentStop","UserPromptSubmit"]`.

---

## 4. Verify each hook fires correctly

Each hook reads JSON from stdin and emits JSON to stdout. You can fire them by hand using the test fixtures.

```bash
TESTS=/home/criznguyen/projects/claude-skills/opinions/model-routing/tests/fixtures
HOOKS=~/.claude/hooks/cqr
```

### 4.1 user-prompt-submit.sh — keyword fence

```bash
"$HOOKS"/user-prompt-submit.sh < "$TESTS/01-user-prompt-keyword.json" | jq .
```

Expected: a JSON object with `hookSpecificOutput.additionalContext` containing the substring `hard-locked Opus zone` and `keyword 'security'`.

### 4.2 lock-opus.sh — destructive Bash command

```bash
"$HOOKS"/lock-opus.sh < "$TESTS/02-lock-opus-bash-rm.json" | jq .
ls ~/.claude/state/lock-opus.flag && echo "flag set"
```

Expected: `additionalContext` mentions `LOCK-OPUS` + `rm -rf`, and `~/.claude/state/lock-opus.flag` exists.

### 4.3 post-tool-use-failure.sh — counter ≥ 2 escalation

```bash
# First failure: silent (count=1)
"$HOOKS"/post-tool-use-failure.sh < "$TESTS/03-tool-failure.json" | jq .
# Second failure: emits TRIPWIRE-ESCALATE (count=2)
"$HOOKS"/post-tool-use-failure.sh < "$TESTS/03-tool-failure.json" | jq .
cat ~/.claude/state/tripwire-cqr-test-session.txt
```

Expected: first call empty/no advisory; second call emits `additionalContext` containing `TRIPWIRE-ESCALATE` and `2 tool failures`. The counter file shows 2 lines.

### 4.4 subagent-stop.sh — refusal pattern in transcript

```bash
"$HOOKS"/subagent-stop.sh < "$TESTS/04-subagent-stop-refusal.json" | jq .
```

Expected: `additionalContext` contains `SUBAGENT-ESCALATE` and the matched refusal phrase.

### 4.5 diff-size-tripwire.sh — large diff sets carry-over flag

```bash
"$HOOKS"/diff-size-tripwire.sh < "$TESTS/05-diff-size-large-write.json" | jq .
ls ~/.claude/state/escalate-next-cqr-test-session.flag && echo "flag set"
```

Expected: `additionalContext` mentions `DIFF-SIZE-TRIPWIRE` and the line count > 150; the per-session escalate flag exists.

---

## 5. Smoke-test inside Claude Code

Open a fresh Claude Code session in any directory **not** under a hard-locked path:

```text
> summarize README.md
```

Watch the log:

```bash
tail -f ~/.claude/cqr-hooks.log
```

Expected: a `[user-prompt-submit] ADVISORY: ROUTING-HINT: prompt looks trivial` line. The agent itself should now have an injected hint suggesting Haiku for any sub-agent it spawns this turn.

Now try a hard-locked prompt:

```text
> review the auth flow for a security audit
```

Expected log line: `[user-prompt-submit] ADVISORY: ROUTING-HINT: hard-locked Opus zone — keyword 'audit'`.

---

## 6. Cleanup of stale state

The hooks accumulate `~/.claude/state/tripwire-<session_id>.txt`, `escalate-next-<session_id>.flag`, etc. Anthropic doesn't expose a session-end hook in the 13-event taxonomy that's universal across all Claude Code builds, so prune these manually with cron or on shell login:

```bash
# Add to ~/.bashrc or a daily cron
find ~/.claude/state -name 'tripwire-*.txt'        -mtime +1 -delete 2>/dev/null
find ~/.claude/state -name 'escalate-next-*.flag'  -mtime +1 -delete 2>/dev/null
find ~/.claude/state -name 'lock-opus.flag'        -mmin +60 -delete 2>/dev/null
```

The hook log itself rotates weekly (in-band — each hook checks `mtime` on entry).

---

## 7. What to do if a hook misfires

Don't disable Claude Code. Instead, see `ROLLBACK.md` for per-hook and whole-subsystem disable procedures.

---

## 8. Cost overhead

Each hook adds ~5–20 ms to the affected event. UserPromptSubmit fires once per turn; PostToolUse fires once per Edit/Write/Bash. Worst-case overhead on a 200-turn week is < 1 minute total, well under the projected $50–70/month savings.
