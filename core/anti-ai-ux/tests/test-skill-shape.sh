#!/usr/bin/env bash
# test-skill-shape.sh — shape tests for core/anti-ai-ux/.
#
# Pure docs skill (no hooks, no runtime); the integrity guarantees are:
#  T1 SKILL.md exists and front-matter has required keys (name, description)
#  T2 README.md exists and is non-empty
#  T3 All 5 prompts/*.md files exist (streaming, rollback, reasoning, consent-destructive, data-flow)
#  T4 Each prompt file has >= 3 fenced code blocks (at least one per supported framework)
#  T5 Each prompt file has an "Anti-pattern" or "Anti-patterns" section heading
#  T6 SKILL.md references all 5 prompt files (defensive against rename drift)
#  T7 SKILL.md front-matter description is 200..900 chars (auto-attach quality;
#     existing skills like core/audit and core/quarantine-pack land ~620-660)
#  T8 Each prompt mentions every documented framework (react/vue/svelte/flutter/
#     swiftui) — drift guard added v1.5.0 cycle-1 closing v1.5.0-AAUX-001.
#
# Usage: bash core/anti-ai-ux/tests/test-skill-shape.sh
# Exit 0 = all PASS; exit 1 = any FAIL.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
README_MD="$SKILL_DIR/README.md"
PROMPTS_DIR="$SKILL_DIR/prompts"

PASS=0
FAIL=0
RESULTS=()

record() {
  local name="$1" cond="$2" detail="$3"
  if [ "$cond" = "1" ]; then
    PASS=$((PASS+1))
    RESULTS+=("PASS  $name")
  else
    FAIL=$((FAIL+1))
    RESULTS+=("FAIL  $name -- $detail")
  fi
}

# T1 — SKILL.md exists + front-matter has name + description
t1_skill_md_frontmatter() {
  if [ ! -f "$SKILL_MD" ]; then
    record "T1 SKILL.md exists with name+description front-matter" 0 "missing $SKILL_MD"
    return
  fi
  # Pull lines between the first two `---` markers
  local fm
  fm="$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$SKILL_MD")"
  local has_name has_desc
  has_name=$(printf '%s\n' "$fm" | grep -c '^name:[[:space:]]*anti-ai-ux[[:space:]]*$' || true)
  has_desc=$(printf '%s\n' "$fm" | grep -c '^description:' || true)
  if [ "$has_name" -ge 1 ] && [ "$has_desc" -ge 1 ]; then
    record "T1 SKILL.md exists with name+description front-matter" 1 ""
  else
    record "T1 SKILL.md exists with name+description front-matter" 0 \
      "name=$has_name desc=$has_desc"
  fi
}

# T2 — README.md exists + non-empty
t2_readme_nonempty() {
  if [ -f "$README_MD" ] && [ "$(wc -c < "$README_MD")" -gt 200 ]; then
    record "T2 README.md exists and >200 bytes" 1 ""
  else
    record "T2 README.md exists and >200 bytes" 0 "missing or too small: $README_MD"
  fi
}

# T3 — all 5 prompt files exist
t3_prompt_files_exist() {
  local missing=()
  for f in streaming.md rollback.md reasoning.md consent-destructive.md data-flow.md; do
    [ -f "$PROMPTS_DIR/$f" ] || missing+=("$f")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    record "T3 5 prompt files exist (streaming/rollback/reasoning/consent-destructive/data-flow)" 1 ""
  else
    record "T3 5 prompt files exist (streaming/rollback/reasoning/consent-destructive/data-flow)" 0 \
      "missing: ${missing[*]}"
  fi
}

# T4 — each prompt file has >= 3 fenced code blocks
t4_prompt_code_blocks() {
  local fail_files=()
  for f in streaming.md rollback.md reasoning.md consent-destructive.md data-flow.md; do
    local path="$PROMPTS_DIR/$f"
    [ -f "$path" ] || continue
    # Count opening fences ("^```<lang>" lines, even count includes both open and close)
    local fences
    fences=$(grep -cE '^```' "$path" || true)
    # Need >= 6 fence lines (3 open + 3 close)
    if [ "$fences" -lt 6 ]; then
      fail_files+=("$f($fences fence-lines)")
    fi
  done
  if [ "${#fail_files[@]}" -eq 0 ]; then
    record "T4 every prompt has >=3 fenced code blocks" 1 ""
  else
    record "T4 every prompt has >=3 fenced code blocks" 0 \
      "below threshold: ${fail_files[*]}"
  fi
}

# T5 — each prompt file has Anti-pattern(s) section
t5_prompt_antipatterns() {
  local fail_files=()
  for f in streaming.md rollback.md reasoning.md consent-destructive.md data-flow.md; do
    local path="$PROMPTS_DIR/$f"
    [ -f "$path" ] || continue
    if ! grep -qE '^##+[[:space:]]+Anti-?pattern' "$path"; then
      fail_files+=("$f")
    fi
  done
  if [ "${#fail_files[@]}" -eq 0 ]; then
    record "T5 every prompt has an Anti-pattern(s) section" 1 ""
  else
    record "T5 every prompt has an Anti-pattern(s) section" 0 \
      "missing section in: ${fail_files[*]}"
  fi
}

# T6 — SKILL.md references all 5 prompt filenames
t6_skill_references_prompts() {
  if [ ! -f "$SKILL_MD" ]; then
    record "T6 SKILL.md references all 5 prompt files" 0 "SKILL.md missing"
    return
  fi
  local missing=()
  for f in streaming.md rollback.md reasoning.md consent-destructive.md data-flow.md; do
    if ! grep -q "prompts/$f" "$SKILL_MD"; then
      missing+=("$f")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    record "T6 SKILL.md references all 5 prompt files" 1 ""
  else
    record "T6 SKILL.md references all 5 prompt files" 0 \
      "not referenced: ${missing[*]}"
  fi
}

# T7 — front-matter description length 200..900 chars (auto-attach quality)
t7_description_length() {
  if [ ! -f "$SKILL_MD" ]; then
    record "T7 SKILL.md description is 200..900 chars" 0 "SKILL.md missing"
    return
  fi
  # Extract description: line; description may wrap, but our skill keeps it on one line.
  local desc
  desc="$(awk '/^description:[[:space:]]*/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$SKILL_MD")"
  local len="${#desc}"
  if [ "$len" -ge 200 ] && [ "$len" -le 900 ]; then
    record "T7 SKILL.md description is 200..900 chars (got $len)" 1 ""
  else
    record "T7 SKILL.md description is 200..900 chars (got $len)" 0 \
      "description length $len out of range"
  fi
}

# T8 — every documented framework appears in every prompt file (case-insensitive)
t8_framework_coverage() {
  local frameworks=(react vue svelte flutter swiftui)
  local fail_files=()
  for f in streaming.md rollback.md reasoning.md consent-destructive.md data-flow.md; do
    local path="$PROMPTS_DIR/$f"
    [ -f "$path" ] || continue
    local missing=()
    for fw in "${frameworks[@]}"; do
      if ! grep -qi "$fw" "$path"; then
        missing+=("$fw")
      fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
      fail_files+=("$f(missing: ${missing[*]})")
    fi
  done
  if [ "${#fail_files[@]}" -eq 0 ]; then
    record "T8 every prompt covers all 5 frameworks (react/vue/svelte/flutter/swiftui)" 1 ""
  else
    record "T8 every prompt covers all 5 frameworks (react/vue/svelte/flutter/swiftui)" 0 \
      "${fail_files[*]}"
  fi
}

t1_skill_md_frontmatter
t2_readme_nonempty
t3_prompt_files_exist
t4_prompt_code_blocks
t5_prompt_antipatterns
t6_skill_references_prompts
t7_description_length
t8_framework_coverage

echo
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo
echo "test-skill-shape: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
