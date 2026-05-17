#!/usr/bin/env bash
# git-push-gate.sh — PreToolUse hook (matcher: Bash).
#
# Refuses `git push --force` / `--force-with-lease` and `git commit/push --no-verify`
# on protected branches. v2.0 P1 #1 ship.
#
# Decisions:
#   - refused: command pattern matched; branch in protected list; no bypass
#       → exit 2 with stderr advisory.
#   - bypass: command pattern matched but bypass marker/token/disable present
#       → exit 0 + telemetry decision=bypass.
#   - allowed: command does not match force-push/no-verify pattern, OR branch
#       not in protected list → exit 0 silent.
#
# Forbidden content (TM4): no LLM-spawn literals — see test-no-claude-spawn.sh.
#
# Privacy invariant: telemetry persists tool name, decision, branch, reason —
# NEVER the command body. Branch name is a public git ref; not sensitive.

set -uo pipefail

case "${GIT_FORCE_PUSH_GATE_DISABLE:-0}" in 1|true|TRUE|yes|YES)
  exit 0 ;;
esac

INPUT="$(cat || true)"
[ -z "$INPUT" ] && exit 0

HOME_DIR="${HOME:-/root}"
GFP_DIR="${GIT_FORCE_PUSH_GATE_DIR:-$HOME_DIR/.claude/git-force-push-gate}"
GFP_PROTECTED="${GIT_FORCE_PUSH_GATE_PROTECTED:-$GFP_DIR/protected-branches.txt}"
GFP_ALLOW_DIR="${GIT_FORCE_PUSH_GATE_ALLOW_DIR:-$HOME_DIR/.claude/git-force-push-gate-allow}"
GFP_TOKEN_SHA="${GIT_FORCE_PUSH_GATE_TOKEN_SHA:-$GFP_DIR/bypass-token.sha}"
TELEM_FILE="${GOVERNANCE_PACK_TELEMETRY_FILE:-$HOME_DIR/.claude/telemetry.jsonl}"
TELEM_DIR="$(dirname "$TELEM_FILE")"
[ -d "$TELEM_DIR" ] || mkdir -p "$TELEM_DIR" 2>/dev/null || exit 0

# --- 1. Parse stdin ------------------------------------------------------
TOOL_NAME=""
TOOL_COMMAND=""
TOOL_CWD=""
SESSION_ID=""

if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo)"
  TOOL_COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo)"
  TOOL_CWD="$(printf '%s' "$INPUT" | jq -r '.tool_input.cwd // .cwd // ""' 2>/dev/null || echo)"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo)"
elif command -v python3 >/dev/null 2>&1; then
  PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); print(""); print(""); print(""); sys.exit(0)
ti = d.get("tool_input") or {}
if not isinstance(ti, dict): ti = {}
print(d.get("tool_name", "") or "")
print(ti.get("command", "") or "")
print(ti.get("cwd", "") or d.get("cwd", "") or "")
print(d.get("session_id", "") or "")
' 2>/dev/null)"
  TOOL_NAME="$(printf '%s' "$PARSED" | sed -n '1p')"
  TOOL_COMMAND="$(printf '%s' "$PARSED" | sed -n '2p')"
  TOOL_CWD="$(printf '%s' "$PARSED" | sed -n '3p')"
  SESSION_ID="$(printf '%s' "$PARSED" | sed -n '4p')"
else
  exit 0
fi

[ "$TOOL_NAME" = "Bash" ] || exit 0
[ -n "$TOOL_COMMAND" ] || exit 0

# --- 2. Tokenize via argv-aware parser ------------------------------------
# v2.1: substring match would false-trip on a literal `--no-verify` or
# `--force` *inside* a commit message body, e.g.
#   git commit -m "fix: handle --no-verify path"
# Tokenize the command, walk argv looking for the `git <subcommand>`
# boundary, and only match flags that are real argv tokens — not bytes
# inside a quoted string. python3 path preferred (matches §1 fallback);
# bash path uses `eval set --` after a `bash -n` syntax check on a copy.
#
# v1.7.0: also detect the pre-commit→commit-msg rename evasion. If the
# agent renames `.git/hooks/pre-commit` to `.git/hooks/commit-msg`, the
# pre-commit hook stops running on commit, effectively achieving
# `--no-verify` semantics without typing `--no-verify`. Detection:
# inside one shell-meta chunk both `.git/hooks/pre-commit` AND
# `commit-msg` literals are present and the chunk's first command is
# `mv` or `cp` or a heredoc that creates the destination. Fires on
# every branch (analogous to --no-verify).
REASON=""
IS_PUSH=0
if command -v python3 >/dev/null 2>&1; then
  PARSED2="$(printf '%s' "$TOOL_COMMAND" | python3 -c '
import shlex, sys
try:
    toks = shlex.split(sys.stdin.read())
except ValueError:
    print(""); print("0"); sys.exit(0)
# shlex does not split on shell-meta operators (;, &&, ||, |); these
# arrive as their own literal tokens. Chunk the argv so each `git`
# invocation is inspected in isolation.
chunks = [[]]
for t in toks:
    if t in (";", "&&", "||", "|"):
        chunks.append([])
    else:
        chunks[-1].append(t)
reason = ""
is_push = 0
for c in chunks:
    if len(c) < 2:
        continue
    # v1.7.0 hook-rename evasion check on this chunk. Only flag when:
    #   - chunk leading command is a file-mover (mv, cp, install, ln)
    #   - chunk contains a token referencing .git/hooks/pre-commit
    #   - chunk contains a token referencing .git/hooks/commit-msg
    # Both literals must appear as ARGV TOKENS (not bytes inside a
    # quoted message body) — shlex.split already enforces that.
    movers = ("mv", "cp", "install", "ln")
    if c[0] in movers:
        has_precommit = any(".git/hooks/pre-commit" in t for t in c[1:])
        has_commitmsg = any(t.endswith(".git/hooks/commit-msg") or t.endswith("/commit-msg") and ".git/hooks/" in t for t in c[1:])
        # Tighten: commit-msg must be inside a .git/hooks/ path, not a bare word.
        has_commitmsg = any(".git/hooks/commit-msg" in t for t in c[1:])
        if has_precommit and has_commitmsg:
            reason = "hook_rename"; break
    if c[0] != "git":
        continue
    sub = c[1]
    rest = c[2:]
    if sub == "push":
        is_push = 1
        if "--force" in rest or "--force-with-lease" in rest or "-f" in rest:
            reason = "force_push"; break
        if "--no-verify" in rest:
            reason = "no_verify"; break
    elif sub == "commit":
        if "--no-verify" in rest:
            reason = "no_verify"; break
    elif sub == "mv":
        # `git mv .git/hooks/pre-commit .git/hooks/commit-msg` — same
        # evasion via the porcelain wrapper. Inspect rest for both literals.
        has_precommit = any(".git/hooks/pre-commit" in t for t in rest)
        has_commitmsg = any(".git/hooks/commit-msg" in t for t in rest)
        if has_precommit and has_commitmsg:
            reason = "hook_rename"; break
print(reason)
print(is_push)
' 2>/dev/null)"
  REASON="$(printf '%s' "$PARSED2" | sed -n '1p')"
  IS_PUSH="$(printf '%s' "$PARSED2" | sed -n '2p')"
  IS_PUSH="${IS_PUSH:-0}"
else
  # bash fallback. Syntax-check a copy via `bash -n` first so an
  # unbalanced-quote `$TOOL_COMMAND` cannot break out of the eval.
  if printf 'set -- %s\n' "$TOOL_COMMAND" | bash -n 2>/dev/null; then
    # shellcheck disable=SC2086,SC2294
    if eval "set -- $TOOL_COMMAND" 2>/dev/null; then
      GIT_SEEN=0
      SUB=""
      MOVER_SEEN=0
      MOVER_HAS_PC=0
      MOVER_HAS_CM=0
      while [ "$#" -gt 0 ]; do
        case "$1" in
          ";"|"&&"|"||"|"|")
            GIT_SEEN=0; SUB=""
            MOVER_SEEN=0; MOVER_HAS_PC=0; MOVER_HAS_CM=0
            ;;
          mv|cp|install|ln)
            # Only a "first-of-chunk" mover triggers the rename check;
            # we approximate this by treating any mover token NOT preceded
            # by a SUB as the chunk-leading mover.
            if [ "$GIT_SEEN" -eq 0 ]; then
              MOVER_SEEN=1; MOVER_HAS_PC=0; MOVER_HAS_CM=0
            fi
            ;;
          git)
            GIT_SEEN=1; SUB=""
            ;;
          *)
            if [ "$MOVER_SEEN" -eq 1 ]; then
              case "$1" in
                *.git/hooks/pre-commit*) MOVER_HAS_PC=1 ;;
              esac
              case "$1" in
                *.git/hooks/commit-msg*) MOVER_HAS_CM=1 ;;
              esac
              if [ "$MOVER_HAS_PC" -eq 1 ] && [ "$MOVER_HAS_CM" -eq 1 ]; then
                REASON="hook_rename"; break
              fi
            fi
            if [ "$GIT_SEEN" -eq 1 ] && [ -z "$SUB" ]; then
              SUB="$1"
              if [ "$SUB" = "mv" ]; then
                MOVER_SEEN=1; MOVER_HAS_PC=0; MOVER_HAS_CM=0
              fi
              if [ "$SUB" = "push" ]; then
                IS_PUSH=1
              fi
            elif [ "$GIT_SEEN" -eq 1 ] && [ "$SUB" = "push" ]; then
              case "$1" in
                --force|--force-with-lease|-f) REASON="force_push"; break ;;
                --no-verify)                   REASON="no_verify"; break ;;
              esac
            elif [ "$GIT_SEEN" -eq 1 ] && [ "$SUB" = "commit" ]; then
              case "$1" in
                --no-verify) REASON="no_verify"; break ;;
              esac
            fi
            ;;
        esac
        shift
      done
    fi
  fi
fi

# --- 2b. v1.10.0 Co-Authored-By trailer pre-push refusal -----------------
# When the command is a `git push` and no other refusal reason has fired,
# inspect the commits about to be pushed for `Co-Authored-By:` trailers
# referencing Anthropic / Claude. The presence of such a trailer is a
# violation of the operator-standing rule (feedback_no_claude_coauthor) +
# the harness-native attribution.commit field; refusing the push prevents
# the trailer from reaching the remote where it cannot be silently rewritten.
#
# Bypass: GIT_FORCE_PUSH_GATE_ALLOW_CLAUDE_TRAILER={1|true|yes}.
#
# Detection: walk `git log --format=%B <upstream>..HEAD` if an upstream
# is configured; otherwise walk the full HEAD log capped at 50 commits
# (so a fresh repo with no upstream still gets sensible coverage). If
# either git invocation fails (no repo, no commits, etc.) we treat it
# as "nothing to scan" and silently allow — fail-open for infra issues
# is consistent with the rest of this hook (line 8: "Infra failure →
# exit 0").
#
# Pattern is loose enough to catch variants:
#   Co-Authored-By: Claude <noreply@anthropic.com>
#   co-authored-by: Claude Opus 4.x <...@anthropic.com>
#   Co-authored-by: claude-code@anthropic.com
# but rejects bare "claude" tokens elsewhere in the message body. Tight
# regex: a `co-authored-by:` trailer line whose value half names Claude
# OR carries an anthropic.com email — same shape as the existing
# core/governance-pack/hooks/no-coauthor-trailer.sh.
if [ -z "$REASON" ] && [ "${IS_PUSH:-0}" = "1" ]; then
  case "${GIT_FORCE_PUSH_GATE_ALLOW_CLAUDE_TRAILER:-0}" in
    1|true|TRUE|yes|YES) ;;
    *)
      SCAN_CWD="$TOOL_CWD"
      [ -n "$SCAN_CWD" ] || SCAN_CWD="$PWD"
      if [ -d "$SCAN_CWD" ]; then
        # Prefer @{upstream}..HEAD; fall back to HEAD~50..HEAD if no
        # upstream is configured.
        SCAN_LOG=""
        SCAN_LOG="$(cd "$SCAN_CWD" 2>/dev/null && \
          git log --format='%B%x00' '@{upstream}..HEAD' 2>/dev/null)"
        if [ -z "$SCAN_LOG" ]; then
          SCAN_LOG="$(cd "$SCAN_CWD" 2>/dev/null && \
            git log -n 50 --format='%B%x00' HEAD 2>/dev/null)"
        fi
        if [ -n "$SCAN_LOG" ]; then
          if printf '%s' "$SCAN_LOG" | \
             grep -qiE 'co-authored-by:[[:space:]]*[^<\n]*claude([^<\n]*<|@)' \
             || printf '%s' "$SCAN_LOG" | \
             grep -qiE 'co-authored-by:[[:space:]]*[^<\n]*<[^>]*anthropic\.com>'; then
            REASON="coauthor_trailer"
          fi
        fi
      fi
      ;;
  esac
fi

[ -n "$REASON" ] || exit 0

# --- 3. Resolve current branch -------------------------------------------
CURRENT_BRANCH=""
if [ -n "$TOOL_CWD" ] && [ -d "$TOOL_CWD" ]; then
  CURRENT_BRANCH="$(cd "$TOOL_CWD" 2>/dev/null && git symbolic-ref --short HEAD 2>/dev/null || echo)"
fi
if [ -z "$CURRENT_BRANCH" ]; then
  CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo)"
fi
[ -n "$CURRENT_BRANCH" ] || CURRENT_BRANCH="(detached)"

# --- 4. Determine if branch is protected ---------------------------------
IS_PROTECTED=0
case "$REASON" in
  no_verify|hook_rename|coauthor_trailer)
    # --no-verify and pre-commit→commit-msg rename evasion are forbidden
    # on every branch by design — both disable the hook chain we depend on
    # for safety. v1.7.0 added hook_rename per
    # project_claude_skills_v2_0_shipped.md v2.2 candidate.
    # v1.10.0 added coauthor_trailer: pushing a commit that carries the
    # Anthropic / Claude trailer to ANY remote / branch is forbidden by
    # operator-standing rule (feedback_no_claude_coauthor).
    IS_PROTECTED=1
    ;;
  force_push)
    if [ -f "$GFP_PROTECTED" ]; then
      while IFS= read -r pattern || [ -n "$pattern" ]; do
        case "$pattern" in '#'*|'') continue ;; esac
        # shellcheck disable=SC2254
        case "$CURRENT_BRANCH" in
          $pattern) IS_PROTECTED=1; break ;;
        esac
      done < "$GFP_PROTECTED"
    else
      # No file → fail-closed treat main/master/release/* as protected.
      case "$CURRENT_BRANCH" in
        main|master|release/*|production) IS_PROTECTED=1 ;;
      esac
    fi
    ;;
esac

# --- 5. Bypass check -----------------------------------------------------
BYPASS=0
BYPASS_REASON=""
# 5a. Per-branch marker file.
if [ -d "$GFP_ALLOW_DIR" ] && [ -f "$GFP_ALLOW_DIR/$CURRENT_BRANCH" ]; then
  BYPASS=1
  BYPASS_REASON="marker"
fi
# 5b. Per-session bypass token (compare to seeded SHA-pin).
if [ "$BYPASS" -eq 0 ] && [ -n "${GIT_FORCE_PUSH_BYPASS_TOKEN:-}" ] && [ -f "$GFP_TOKEN_SHA" ]; then
  EXPECTED="$(tr -d '[:space:]' < "$GFP_TOKEN_SHA" 2>/dev/null || echo)"
  if [ -n "$EXPECTED" ] && [ "$GIT_FORCE_PUSH_BYPASS_TOKEN" = "$EXPECTED" ]; then
    BYPASS=1
    BYPASS_REASON="token"
  fi
fi

# --- 6. Telemetry --------------------------------------------------------
emit_telemetry() {
  local decision="$1" branch="$2" reason="$3" bypass_reason="$4"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"event":"git-push-gate","ts":"%s","tool":"Bash","decision":"%s","branch":"%s","reason":"%s","bypass_reason":"%s","session_id":"%s"}\n' \
    "$ts" \
    "${decision//\"/}" \
    "${branch//\"/}" \
    "${reason//\"/}" \
    "${bypass_reason//\"/}" \
    "${SESSION_ID//\"/}" \
    >> "$TELEM_FILE" 2>/dev/null || true
}

# --- 7. Decision branches ------------------------------------------------
if [ "$IS_PROTECTED" -eq 0 ]; then
  emit_telemetry "allowed" "$CURRENT_BRANCH" "$REASON" ""
  printf '[git-push-gate-allowed] branch=%s reason=%s (not protected)\n' "$CURRENT_BRANCH" "$REASON" >&2
  exit 0
fi

if [ "$BYPASS" -eq 1 ]; then
  emit_telemetry "bypass" "$CURRENT_BRANCH" "$REASON" "$BYPASS_REASON"
  printf '[git-push-gate-bypass] branch=%s reason=%s bypass=%s\n' "$CURRENT_BRANCH" "$REASON" "$BYPASS_REASON" >&2
  exit 0
fi

emit_telemetry "refused" "$CURRENT_BRANCH" "$REASON" ""
printf '[git-push-gate-refused] branch=%s reason=%s — refusing %s on protected branch\n' \
  "$CURRENT_BRANCH" "$REASON" "$REASON" >&2
case "$REASON" in
  force_push)
    printf 'Bypass options: (1) touch %s/<branch> (2) export GIT_FORCE_PUSH_BYPASS_TOKEN=... (3) export GIT_FORCE_PUSH_GATE_DISABLE=1\n' \
      "$GFP_ALLOW_DIR" >&2
    ;;
  no_verify)
    printf 'Bypass options: (1) export GIT_FORCE_PUSH_BYPASS_TOKEN=... (2) export GIT_FORCE_PUSH_GATE_DISABLE=1 — note: --no-verify is forbidden on every branch by design\n' >&2
    ;;
  hook_rename)
    printf 'Bypass options: (1) export GIT_FORCE_PUSH_BYPASS_TOKEN=... (2) export GIT_FORCE_PUSH_GATE_DISABLE=1 — note: renaming .git/hooks/pre-commit to .git/hooks/commit-msg disables pre-commit verification (--no-verify equivalent) and is forbidden on every branch by design (v1.7.0)\n' >&2
    ;;
  coauthor_trailer)
    printf 'Bypass options: (1) export GIT_FORCE_PUSH_GATE_ALLOW_CLAUDE_TRAILER=1 (2) export GIT_FORCE_PUSH_GATE_DISABLE=1 — but the canonical fix is to amend the offending commit(s) and remove the `Co-Authored-By: Claude` / Anthropic trailer per operator-standing rule (feedback_no_claude_coauthor). v1.10.0 mini-wave addition.\n' >&2
    ;;
esac
exit 2
