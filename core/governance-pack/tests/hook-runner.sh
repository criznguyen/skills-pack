#!/usr/bin/env bash
# hook-runner.sh — test harness for governance-pack hooks.
#
# Invoked by promptfoo `exec:bash` provider. Reads $hook (path) and
# $payload (JSON string) from env, pipes payload to the hook, captures
# exit code + stderr, and prints a single-line summary that promptfoo
# asserts against.
#
# Usage (manual): hook=../hooks/no-coauthor-trailer.sh payload='{...}' ./hook-runner.sh

set -uo pipefail

HOOK_PATH="${hook:?hook env var required}"
PAYLOAD="${payload:-{}}"

# Resolve relative to this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$HOOK_PATH" in
  /*) ABS_HOOK="$HOOK_PATH" ;;
  *)  ABS_HOOK="$SCRIPT_DIR/$HOOK_PATH" ;;
esac

if [ ! -x "$ABS_HOOK" ]; then
  echo "ERROR: hook not executable: $ABS_HOOK"
  exit 1
fi

STDERR_FILE="$(mktemp)"
echo "$PAYLOAD" | "$ABS_HOOK" 2>"$STDERR_FILE" >/dev/null
RC=$?

# Single-line output for promptfoo assertion: rc=N stderr=<full content>
printf 'rc=%d stderr=%s' "$RC" "$(tr '\n' ' ' < "$STDERR_FILE")"
rm -f "$STDERR_FILE"
exit 0
