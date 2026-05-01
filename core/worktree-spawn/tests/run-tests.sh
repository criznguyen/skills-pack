#!/usr/bin/env bash
# run-tests.sh — zero-dependency runner for tests/tasks.yaml.
#
# Parses the `vars.cmd:` blocks out of tasks.yaml and runs each. Used while
# P0-06 (golden-task-eval) hasn't shipped yet; once it has, this same yaml
# will run via promptfoo with no edits.
#
# Exit code: 0 if all tasks PASS; non-zero otherwise.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_FILE="$HERE/tasks.yaml"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"

if [[ ! -f "$TASKS_FILE" ]]; then
  echo "run-tests.sh: tasks.yaml not found at $TASKS_FILE" >&2
  exit 2
fi

# Use python3 to extract the (description, cmd) pairs from the yaml.
mapfile -t TASKS < <(python3 - "$TASKS_FILE" <<'PY'
import sys, re
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# We do a tolerant extraction since we don't want to depend on PyYAML.
# Each task block starts with "  - description:" and contains a "        cmd: |"
# multi-line literal block whose body is indented 10 spaces.
tasks = []
lines = src.splitlines()
i = 0
desc = None
while i < len(lines):
    line = lines[i]
    m_desc = re.match(r"^  - description:\s*[\"']?(.*?)[\"']?\s*$", line)
    if m_desc:
        desc = m_desc.group(1)
    m_cmd = re.match(r"^( {6,8})cmd:\s*\|\s*$", line)
    if m_cmd and desc is not None:
        indent_len = len(m_cmd.group(1)) + 2
        i += 1
        body = []
        while i < len(lines):
            nl = lines[i]
            if nl.strip() == "" :
                body.append("")
                i += 1
                continue
            stripped_indent = len(nl) - len(nl.lstrip(" "))
            if stripped_indent < indent_len and nl.strip() != "":
                break
            body.append(nl[indent_len:] if len(nl) >= indent_len else nl.lstrip())
            i += 1
        tasks.append((desc, "\n".join(body)))
        desc = None
        continue
    i += 1

for d, c in tasks:
    sys.stdout.write("===DESC===\n" + d + "\n===CMD===\n" + c + "\n===END===\n")
PY
)

# Re-split into pairs.
PAIRS=()
buf=""
mode=""
desc=""
cmd=""
for line in "${TASKS[@]}"; do
  case "$line" in
    "===DESC===") mode="desc"; desc=""; cmd="" ;;
    "===CMD===")  mode="cmd" ;;
    "===END===")  PAIRS+=("$desc"$'\x1f'"$cmd"); mode="" ;;
    *)
      if [[ "$mode" == "desc" ]]; then
        desc+="$line"
      elif [[ "$mode" == "cmd" ]]; then
        cmd+="$line"$'\n'
      fi
      ;;
  esac
done

if (( ${#PAIRS[@]} == 0 )); then
  echo "run-tests.sh: no tasks parsed from $TASKS_FILE" >&2
  exit 2
fi

PASS=0
FAIL=0
N=${#PAIRS[@]}

for i in "${!PAIRS[@]}"; do
  pair="${PAIRS[$i]}"
  desc="${pair%%$'\x1f'*}"
  cmd="${pair#*$'\x1f'}"
  printf '\n[%d/%d] %s\n' "$((i+1))" "$N" "$desc"
  printf '%s\n' "------------------------------------------------------------------"
  # The cmd uses `dirname "$0"` to find scripts; we set $0 to the tasks.yaml
  # path so its parent is the skill root.
  out="$(bash -c "$cmd" "$TASKS_FILE" 2>&1)"
  rc=$?
  printf '%s\n' "$out"
  printf '%s\n' "------------------------------------------------------------------"
  if (( rc == 0 )) && echo "$out" | grep -q "^PASS$"; then
    printf 'RESULT: PASS\n'
    PASS=$((PASS+1))
  else
    printf 'RESULT: FAIL (rc=%d)\n' "$rc"
    FAIL=$((FAIL+1))
  fi
done

printf '\n=== summary ===\n'
printf 'pass: %d / %d\n' "$PASS" "$N"
printf 'fail: %d / %d\n' "$FAIL" "$N"
(( FAIL == 0 ))
