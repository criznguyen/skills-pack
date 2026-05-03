#!/usr/bin/env bash
# test-skill-shape.sh — shape tests for core/fix-root-cause/.
#
# Pure docs skill (no hooks, no runtime); the integrity guarantees are:
#  T1 SKILL.md exists and front-matter has required keys (name, description)
#  T2 README.md exists and is non-empty
#  T3 All 3 prompt files exist (decision-tree, anti-pattern-catalog, workaround-template)
#  T4 Anti-pattern catalog has >= 12 entries (count headings of form "## Entry N")
#  T5 Decision tree has a mermaid syntax block (```mermaid ... ```)
#  T6 Decision tree has a plain-text fallback section (heading "Plain-text fallback")
#  T7 Workaround template has all 5 standard fields (WORKAROUND, Why root cause not fixed,
#     Follow-up, Reversibility, Author)
#  T8 SKILL.md front-matter description is 200..900 chars (auto-attach quality;
#     existing skills like core/audit, core/quarantine-pack, core/anti-ai-ux land in this band)
#  T9 SKILL.md references all 3 prompt files (defensive against rename drift)
#
# Usage: bash core/fix-root-cause/tests/test-skill-shape.sh
# Exit 0 = all PASS; exit 1 = any FAIL.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
README_MD="$SKILL_DIR/README.md"
PROMPTS_DIR="$SKILL_DIR/prompts"
DECISION_TREE="$PROMPTS_DIR/decision-tree.md"
CATALOG="$PROMPTS_DIR/anti-pattern-catalog.md"
TEMPLATE="$PROMPTS_DIR/workaround-template.md"

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
  local fm
  fm="$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$SKILL_MD")"
  local has_name has_desc
  has_name=$(printf '%s\n' "$fm" | grep -c '^name:[[:space:]]*fix-root-cause[[:space:]]*$' || true)
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

# T3 — all 3 prompt files exist
t3_prompt_files_exist() {
  local missing=()
  for f in decision-tree.md anti-pattern-catalog.md workaround-template.md; do
    [ -f "$PROMPTS_DIR/$f" ] || missing+=("$f")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    record "T3 3 prompt files exist (decision-tree/anti-pattern-catalog/workaround-template)" 1 ""
  else
    record "T3 3 prompt files exist (decision-tree/anti-pattern-catalog/workaround-template)" 0 \
      "missing: ${missing[*]}"
  fi
}

# T4 — anti-pattern catalog has >= 12 entries
t4_catalog_entry_count() {
  if [ ! -f "$CATALOG" ]; then
    record "T4 anti-pattern-catalog has >=12 entries" 0 "catalog missing"
    return
  fi
  local entries
  entries=$(grep -cE '^## Entry [0-9]+' "$CATALOG" || true)
  if [ "$entries" -ge 12 ]; then
    record "T4 anti-pattern-catalog has >=12 entries (got $entries)" 1 ""
  else
    record "T4 anti-pattern-catalog has >=12 entries (got $entries)" 0 \
      "expected >=12, got $entries"
  fi
}

# T5 — decision tree has a mermaid block
t5_decision_tree_mermaid() {
  if [ ! -f "$DECISION_TREE" ]; then
    record "T5 decision-tree has mermaid block" 0 "decision-tree.md missing"
    return
  fi
  if grep -qE '^```mermaid[[:space:]]*$' "$DECISION_TREE"; then
    record "T5 decision-tree has mermaid block" 1 ""
  else
    record "T5 decision-tree has mermaid block" 0 \
      "no \`\`\`mermaid fence found"
  fi
}

# T6 — decision tree has a plain-text fallback section
t6_decision_tree_fallback() {
  if [ ! -f "$DECISION_TREE" ]; then
    record "T6 decision-tree has plain-text fallback section" 0 "decision-tree.md missing"
    return
  fi
  if grep -qiE '^##+[[:space:]]+Plain-?text[[:space:]]+fallback' "$DECISION_TREE"; then
    record "T6 decision-tree has plain-text fallback section" 1 ""
  else
    record "T6 decision-tree has plain-text fallback section" 0 \
      "missing 'Plain-text fallback' section heading"
  fi
}

# T7 — workaround template has all 5 standard fields
t7_template_fields() {
  if [ ! -f "$TEMPLATE" ]; then
    record "T7 workaround-template has all 5 standard fields" 0 "template missing"
    return
  fi
  local missing=()
  # Order matches the documented standard
  for field in "WORKAROUND:" "Why root cause not fixed:" "Follow-up:" "Reversibility:" "Author:"; do
    if ! grep -qF "$field" "$TEMPLATE"; then
      missing+=("$field")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    record "T7 workaround-template has all 5 standard fields" 1 ""
  else
    record "T7 workaround-template has all 5 standard fields" 0 \
      "missing field markers: ${missing[*]}"
  fi
}

# T8 — front-matter description length 200..900 chars (auto-attach quality)
t8_description_length() {
  if [ ! -f "$SKILL_MD" ]; then
    record "T8 SKILL.md description is 200..900 chars" 0 "SKILL.md missing"
    return
  fi
  local desc
  desc="$(awk '/^description:[[:space:]]*/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$SKILL_MD")"
  local len="${#desc}"
  if [ "$len" -ge 200 ] && [ "$len" -le 900 ]; then
    record "T8 SKILL.md description is 200..900 chars (got $len)" 1 ""
  else
    record "T8 SKILL.md description is 200..900 chars (got $len)" 0 \
      "description length $len out of range"
  fi
}

# T9 — SKILL.md references all 3 prompt filenames
t9_skill_references_prompts() {
  if [ ! -f "$SKILL_MD" ]; then
    record "T9 SKILL.md references all 3 prompt files" 0 "SKILL.md missing"
    return
  fi
  local missing=()
  for f in decision-tree.md anti-pattern-catalog.md workaround-template.md; do
    if ! grep -q "prompts/$f" "$SKILL_MD"; then
      missing+=("$f")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    record "T9 SKILL.md references all 3 prompt files" 1 ""
  else
    record "T9 SKILL.md references all 3 prompt files" 0 \
      "not referenced: ${missing[*]}"
  fi
}

t1_skill_md_frontmatter
t2_readme_nonempty
t3_prompt_files_exist
t4_catalog_entry_count
t5_decision_tree_mermaid
t6_decision_tree_fallback
t7_template_fields
t8_description_length
t9_skill_references_prompts

echo
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo
echo "test-skill-shape: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
