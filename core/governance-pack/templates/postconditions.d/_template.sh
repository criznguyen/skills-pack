#!/usr/bin/env bash
# Authoring template — copy to a new filename (e.g. `myskill.sh`) and customize.
# match=Bash                       # one of: Bash | Edit | Write | MultiEdit | NotebookEdit
# trigger=*                        # bash glob against tool_input command + file_path; `*` = always
# verify_substring=                # optional: literal substring required in stdout (NOT regex)
# timeout_override=                # optional: per-postcondition timeout in seconds (max 30)
#
# Available env vars (exported by core/governance-pack/hooks/postcondition-hook.sh):
#   CLAUDE_TOOL_NAME              — e.g. "Bash" / "Edit"
#   CLAUDE_TOOL_INPUT_FILE_PATH   — path arg (Edit / Write / MultiEdit)
#   CLAUDE_TOOL_INPUT_COMMAND     — command string (Bash)
#   CLAUDE_TOOL_EXIT_CODE         — tool_response.exit_code (Bash)
#   CLAUDE_TOOL_STDOUT_FILE       — path to file holding tool_response.stdout (when present)
#
# FORBIDDEN content (TM5 / spec NG4) — see core/governance-pack/README.md
# §"Authoring postcondition snippets" for the canonical list. In short:
# postcondition bodies MUST NOT spawn an LLM (no claude-CLI invocation,
# no sub-agent helper tool, no Anthropic API call). Postconditions are
# deterministic shell ONLY. The assertion is "world matches claim",
# never "claim is semantically right".
#
# Body convention: emit verification command(s); exit 0 = pass, non-zero = fail.
set -uo pipefail
echo "<replace this echo with verification commands; exit non-zero on fail>"
exit 1  # CHANGE: real postcondition exits 0 on success
