#!/usr/bin/env bash
# _self-write.sh — TM1 integrity check (architecture §4), Write-event sibling.
# Sibling of _self.sh; matches `Write` to close TM1 layer (a) coverage gap from cycle-1 audit PC-H1.
# match=Write
# trigger=*postconditions.d*
#
# Fires when the agent writes (creates) a file under ~/.claude/postconditions.d/.
# Asserts the written file body contains at least one verification verb
# (test/stat/grep/ls/jq/git/find/[/[[/python3/node/npm/cargo/go).
# A bare `exit 0` postcondition would silently disable the gate — TM1.
# Shadow-mode surfaces the trip in JSONL telemetry; blocking-mode `exit 2`s.
#
# Lex-ordered first (filename starts with `_`), so it runs ahead of the
# functional defaults — by design, since a tampered postcondition could
# otherwise mask its own integrity check.
set -uo pipefail
F="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"
[ -z "$F" ] && exit 0
case "$F" in
  *postconditions.d*) ;;
  *) exit 0 ;;
esac
[ -f "$F" ] || exit 0

# Skip the template — its body is a placeholder that legitimately
# contains `exit 1`, and the hook never executes it because no
# operator postcondition matches `_template.sh`.
case "$(basename "$F")" in
  _template.sh) exit 0 ;;
esac

# Strip comments + blank lines, then look for any verification verb.
# Note: tech-spec §1.2 sketched `\b\[\b` for the bracket primitive but `\b`
# only matches at word/non-word transitions and `[` is non-word, so word-
# boundary anchors never fire on bare `[`. The regex below uses character-
# class anchors (start-of-line, whitespace, semicolon) so the `[` and `[[`
# test commands match in their natural contexts (`if [ -f X ]`,
# `[[ -n "$X" ]]`). Word entries keep `\b` for tight matching.
# Documented in docs/sdlc/decisions/postcondition-hook.md §10.
if ! grep -vE '^\s*(#|$)' "$F" | \
     grep -qE '\b(test|stat|grep|ls|jq|git|find|python3?|node|npm|cargo|go|awk|printf|sed|tr|cmp|diff|head|tail)\b|(^|[[:space:]])\[\[?[[:space:]]'; then
  echo "[postcondition _self-write] $F has no verification verb — would silently disable gate (TM1)" >&2
  exit 1
fi
exit 0
