#!/usr/bin/env bash
# Unit tests for core/core-config/hooks/block-destructive.sh
# 33 cases: 14 destructive (exit 2) + 8 benign (exit 0) + 1 opt-out
# + 1 malformed-JSON + 4 AUDIT-V142-002/003 regression cases (3 destructive
# variants previously bypassed: rm --recursive --force /, rm -rf foo /,
# rm --recursive --force /home /; plus 1 silent-opt-out stderr-empty
# regression for AUDIT-V142-003) + 5 v1.4.4 doc-context cases (D15-D19:
# git-commit / echo / heredoc carry destructive patterns as TEXT and must
# pass; actual destructive invocations and chained-after-doc still block).
# Pure-shell harness; no bats.
#
# Usage: bash core/core-config/tests/test-block-destructive.sh
# Exit 0 = all PASS; exit 1 = any FAIL.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOOK="${REPO_ROOT}/core/core-config/hooks/block-destructive.sh"

if [[ ! -x "${HOOK}" ]]; then
  echo "FAIL: hook not executable at ${HOOK}" >&2
  exit 1
fi

pass=0
fail=0
results=()

check() {
  local name="$1" want_exit="$2" stdin="$3" want_stderr_substr="$4"
  shift 4
  local actual_exit actual_stderr
  actual_stderr="$(printf '%s' "${stdin}" | env "$@" bash "${HOOK}" 2>&1 1>/dev/null)"
  actual_exit=$?
  if [[ "${actual_exit}" -ne "${want_exit}" ]]; then
    fail=$((fail+1))
    results+=("FAIL ${name}: want exit ${want_exit}, got ${actual_exit} (stderr=${actual_stderr})")
    return
  fi
  if [[ -n "${want_stderr_substr}" ]] && ! grep -qF -- "${want_stderr_substr}" <<< "${actual_stderr}"; then
    fail=$((fail+1))
    results+=("FAIL ${name}: stderr missing '${want_stderr_substr}' (got: ${actual_stderr})")
    return
  fi
  pass=$((pass+1))
  results+=("PASS ${name}")
}

# Helper to wrap a command in the standard PreToolUse Bash JSON.
mkj() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }

# ---- 14 destructive cases (exit 2) ----
check "D1 rm -rf /"                      2 "$(mkj 'rm -rf /')"                            "rm -rf /"
check "D2 rm -rf ~"                      2 "$(mkj 'rm -rf ~')"                            "rm -rf ~"
check "D3 rm -rf \$HOME"                 2 "$(mkj 'rm -rf $HOME')"                        "rm -rf \$HOME"
check "D4 rm -rf ."                      2 "$(mkj 'rm -rf .')"                            "rm -rf ."
check "D5 rm -rf /usr"                   2 "$(mkj 'rm -rf /usr')"                         "system-dir"
check "D6 mkfs.ext4"                     2 "$(mkj 'mkfs.ext4 /dev/sdb1')"                 "mkfs"
check "D7 dd of=/dev/sda"                2 "$(mkj 'dd if=/dev/zero of=/dev/sda bs=1M')"   "dd to raw disk"
check "D8 cat > /dev/sda"                2 "$(mkj 'cat foo > /dev/sda')"                  "redirect to raw disk"
check "D9 chmod -R 777 /"                2 "$(mkj 'chmod -R 777 /')"                      "chmod -R 777"
check "D10 chown -R user /"              2 "$(mkj 'chown -R user:user /')"                "chown"
check "D11 terraform destroy"            2 "$(mkj 'terraform destroy')"                   "terraform destroy"
check "D12 kubectl delete ns --all"      2 "$(mkj 'kubectl delete ns --all')"             "kubectl delete ns"
check "D13 fork bomb"                    2 "$(mkj ':(){ :|:& };:')"                       "fork bomb"
check "D14 shutdown -h now"              2 "$(mkj 'shutdown -h now')"                     "system halt"

# ---- 8 benign cases (exit 0, silent) ----
check "B1 ls"                            0 "$(mkj 'ls')"                                  ""
check "B2 git status"                    0 "$(mkj 'git status')"                          ""
check "B3 rm file.txt"                   0 "$(mkj 'rm file.txt')"                         ""
check "B4 rm -rf node_modules"           0 "$(mkj 'rm -rf node_modules')"                 ""
check "B5 terraform destroy -target"     0 "$(mkj 'terraform destroy -target=foo.bar')"   ""
check "B6 kubectl delete pod nginx"      0 "$(mkj 'kubectl delete pod nginx')"            ""
check "B7 dd if=foo of=bar.bin"          0 "$(mkj 'dd if=foo of=bar.bin')"                ""
check "B8 chmod 755 file"                0 "$(mkj 'chmod 755 file')"                      ""

# ---- 1 opt-out case ----
check "O1 BLOCK_DESTRUCTIVE_DISABLE=1"   0 "$(mkj 'rm -rf /')"                            "" \
  BLOCK_DESTRUCTIVE_DISABLE=1

# ---- 1 malformed-JSON case ----
check "M1 malformed-JSON"                0 'not-json{'                                    ""

# ---- AUDIT-V142-002 regression: flag-cluster + multi-target rm bypasses ----
# Audit probes P12 (long-form), P8 (multi-target), and a long-form+multi combo.
check "R1 rm --recursive --force /"        2 "$(mkj 'rm --recursive --force /')"          "rm -rf /"
check "R2 rm -rf foo /"                    2 "$(mkj 'rm -rf foo /')"                      "rm -rf /"
check "R3 rm --recursive --force /home /"  2 "$(mkj 'rm --recursive --force /home /')"    "rm -rf /"

# ---- v1.4.4 doc-context whitelist (D15-D19) ----
# Destructive patterns inside text payloads of doc/commit ops are descriptions,
# not invocations. Must pass. But chained-after-doc destructive halves still
# block.
check "D15 git-commit destructive text"   0 "$(mkj 'git commit -m fix-rm-rf-pattern-in-regex')" ""
check "D16 echo destructive text"         0 "$(mkj 'echo rm -rf / is dangerous')"               ""
# D17 uses JSON-encoded \n (literal backslash-n) per Claude Code hook contract;
# real PreToolUse JSON never embeds raw newlines in the command string.
check "D17 heredoc body destructive"      0 "$(mkj 'cat > file <<EOF\nrm -rf /\nEOF')"          ""
check "D18 actual rm -rf still blocks"    2 "$(mkj 'rm -rf /')"                                  "rm -rf /"
check "D19 chained dest after git commit" 2 "$(mkj 'git commit -m doc && rm -rf /')"             "rm -rf /"

# ---- AUDIT-V142-003 regression: opt-out must exit 0 silent (no stderr) ----
silent_stderr="$(BLOCK_DESTRUCTIVE_DISABLE=1 bash "${HOOK}" <<< "$(mkj 'rm -rf /')" 2>&1 1>/dev/null)"
silent_exit=$?
if [[ "${silent_exit}" -eq 0 && -z "${silent_stderr}" ]]; then
  pass=$((pass+1))
  results+=("PASS R4 opt-out silent (no stderr)")
else
  fail=$((fail+1))
  results+=("FAIL R4 opt-out silent: exit=${silent_exit} stderr=[${silent_stderr}]")
fi

total=$((pass+fail))
echo
for line in "${results[@]}"; do
  echo "  ${line}"
done
echo
if [[ ${fail} -eq 0 ]]; then
  echo "RESULT: ${pass}/${total} PASS"
  exit 0
else
  echo "RESULT: ${pass}/${total} PASS, ${fail} FAIL"
  exit 1
fi
