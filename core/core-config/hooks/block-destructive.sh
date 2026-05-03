#!/usr/bin/env bash
set -euo pipefail

# core-config / block-destructive
# PreToolUse hook for Bash. Substring-regex blacklist of catastrophic shell
# patterns that other hooks (blast-radius.sh, git-force-push-gate) do NOT
# already cover. Composes UNDER blast-radius — blast-radius runs first with
# its escalation taxonomy; this hook is the broader-net second layer that
# catches mkfs, dd-to-raw-disk, fork bombs, kubectl delete --all, etc.
#
# Exit 0 silent  = command does not match any blacklist pattern, OR skip case
#                  (tool != Bash, malformed JSON, opt-out env, no command field)
# Exit 2 + stderr = command matches; stderr names the matched pattern
#
# Opt-out: BLOCK_DESTRUCTIVE_DISABLE={1,true,TRUE} → exit 0 silent regardless.
#
# Doc-context whitelist (v1.4.4): destructive patterns appearing inside the
# TEXT PAYLOAD of a documentation/commit-message op (e.g. `git commit -m
# "fix: rm -rf / pattern"`, `echo "rm -rf / is dangerous"`, `cat > file <<EOF
# ... rm -rf / ... EOF`) are NOT actual destructive ops — the operator is
# describing the rule, not invoking it. Discovered v1.4.2.1 ship: orchestrator
# had to reword its own CHANGELOG description. The whitelist covers commands
# whose ENTIRE shape is doc-emission. Chained commands (`&&`, `;`, `|`, `||`)
# bypass the whitelist so `git commit && rm -rf /` still blocks on the second
# token. See test cases D15-D19 for the contract.
#
# Latency budget <50ms p99: pure regex match; no subshell beyond grep, no
# fork to external services. Negative-lookahead patterns (terraform destroy
# without -target; system-halt without --help) implemented via two-step
# grep to keep the hook portable to BSD grep (which lacks PCRE -P).

if [[ "${BLOCK_DESTRUCTIVE_DISABLE:-}" =~ ^(1|true|TRUE)$ ]]; then
  exit 0
fi

INPUT="$(cat 2>/dev/null || true)"
if [[ -z "${INPUT}" ]]; then
  exit 0
fi

tool_name="$(printf '%s' "${INPUT}" \
  | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -n1)"
if [[ "${tool_name}" != "Bash" ]]; then
  exit 0
fi

cmd="$(printf '%s' "${INPUT}" \
  | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 \
  | sed -e 's/^"command"[[:space:]]*:[[:space:]]*"//' -e 's/"$//')"
if [[ -z "${cmd}" ]]; then
  exit 0
fi

block() {
  local pattern_name="$1"
  printf '[block-destructive] refusing %s (matched pattern: %s)\n' \
    "${cmd}" "${pattern_name}" >&2
  exit 2
}

match() { printf '%s' "${cmd}" | grep -qE -- "$1"; }

# ---- v1.4.4 doc-context whitelist ----
# If the command is SOLELY a doc/commit-msg op (no shell chaining), destructive
# patterns inside the text payload are descriptions, not invocations. Skip the
# destructive scan. Chained commands keep the scan active so the destructive
# half of `git commit && rm -rf /` is still caught.
if ! [[ "${cmd}" =~ [\;\&\|] ]]; then
  case "${cmd}" in
    "git commit "*|"git tag "*|"printf "*|"echo "*|"cat > "*|"cat >> "*)
      exit 0
      ;;
  esac
fi
# Heredoc body of any command that writes a file is doc — even chained, the
# heredoc body is purely text data, not executable. Match the canonical EOF
# heredoc marker form (`<<EOF`, `<<-EOF`, `<<'EOF'`, `<<"EOF"`). Match the
# delimiter ANYWHERE in the command string; we don't insist on what follows
# because heredoc bodies are wrapped in newlines or escaped newlines that
# vary by JSON encoding.
if printf '%s' "${cmd}" | grep -qE '<<-?[[:space:]]*['\''"]?EOF'; then
  exit 0
fi

# Flag-cluster prefix used by the rm rules below. Matches a chain of one or
# more `-x` / `--xx` flag tokens where at least one flag carries a destructive
# letter (r/R/f/F), followed by zero or more intervening non-destructive
# target tokens. Covers single-dash + long-form + multi-target rm forms:
#   rm -rf /                            (single short flag)
#   rm -fr /                            (flag-letter order)
#   rm -Rf /                            (capital R)
#   rm --recursive --force /            (long-form chain — AUDIT-V142-002)
#   rm -rf foo /                        (multi-target, dangerous last — AUDIT-V142-002)
#   rm --recursive --force /home /      (long-form + multi-target combo)
RM_DESTRUCTIVE_PREFIX='rm[[:space:]]+(-{1,2}[a-zA-Z-]*[rRfF][a-zA-Z-]*[[:space:]]+)+([^[:space:];&|]+[[:space:]]+)*'

# 1. rm -rf /  (literal root; explicit `*` glob also caught)
match "${RM_DESTRUCTIVE_PREFIX}/([[:space:]]|\$|\\*)" && block 'rm -rf /'

# 2. rm -rf ~  (bare $HOME glob shorthand)
match "${RM_DESTRUCTIVE_PREFIX}~([[:space:]]|\$|/)" && block 'rm -rf ~'

# 3. rm -rf $HOME  (literal envvar form)
match "${RM_DESTRUCTIVE_PREFIX}\\\$HOME([[:space:]]|\$|/)" && block 'rm -rf $HOME'

# 4. rm -rf .  (cwd recursive — usually not what the operator meant)
match "${RM_DESTRUCTIVE_PREFIX}\\.([[:space:]]|\$)" && block 'rm -rf .'

# 5. rm -rf /usr|/etc|/var|... (system dirs)
match "${RM_DESTRUCTIVE_PREFIX}/(usr|etc|var|boot|bin|sbin|lib|lib64|opt|root)([[:space:]]|\$|/)" \
  && block 'rm -rf /system-dir'

# 6. mkfs (any filesystem format)
match 'mkfs(\.|[[:space:]])' && block 'mkfs (filesystem format)'

# 7. dd of=/dev/sd*|nvme*|hd*|mmcblk* (raw-disk write)
match 'dd[[:space:]]+.*of=/dev/(sd|nvme|hd|mmcblk)' && block 'dd to raw disk'

# 8. > /dev/sd*|nvme*|hd* (redirect to raw disk)
match '>[[:space:]]*/dev/(sd|nvme|hd)[a-z]' && block 'redirect to raw disk'

# 9. chmod -R 777 /  (world-writable root)
match 'chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/([[:space:]]|$)' \
  && block 'chmod -R 777 /'

# 10. chown -R ... /  (recursive ownership change of root)
match 'chown[[:space:]]+-R[[:space:]]+[^[:space:]]+[[:space:]]+/([[:space:]]|$)' \
  && block 'chown -R … /'

# 11. terraform destroy WITHOUT -target  (two-step: matches broad pattern,
#     then negative re-test to exclude the -target safe-suffix)
if match '(^|[[:space:];&|])terraform[[:space:]]+destroy([[:space:]]|$)'; then
  if ! printf '%s' "${cmd}" | grep -qE -- '(^|[[:space:];&|])terraform[[:space:]]+destroy[^|;&]*-target'; then
    block 'terraform destroy without -target'
  fi
fi

# 12. kubectl delete ns|namespace --all
match '(^|[[:space:];&|])kubectl[[:space:]]+delete[[:space:]]+(ns|namespace)[[:space:]]+--all([[:space:]]|$)' \
  && block 'kubectl delete ns --all'

# 13. fork bomb (canonical shape :(){ :|:& };:)
match ':\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:' && block 'fork bomb'

# 14. shutdown / reboot / halt / poweroff WITHOUT --help (two-step)
if match '(^|[[:space:];&|])(shutdown|reboot|halt|poweroff)([[:space:]]|$)'; then
  if ! printf '%s' "${cmd}" | grep -qE -- '(^|[[:space:];&|])(shutdown|reboot|halt|poweroff)[[:space:]]+--help'; then
    block 'system halt (shutdown/reboot/halt/poweroff)'
  fi
fi

exit 0
