#!/usr/bin/env bash
# test-tool-class-counters.sh — v1.7.0 dual-counter (read-class vs write-class) tests.
#
# Asserts:
#   T-LCB-1  200 Read calls under default ceilings (read=600/write=150) DO NOT halt.
#   T-LCB-2  101 Read calls with LOOP_BREAKER_READ_CEILING=100 → halts on read_count.
#   T-LCB-3  151 Edit calls under default ceilings DO halt on write_count.
#   T-LCB-4  100 Read + 100 Edit (no global cap set) DO NOT halt (each under its class ceiling).
#   T-LCB-5  100 Read + 151 Edit halt on write_count, not read_count.
#   T-LCB-6  Backward compat — LOOP_BREAKER_ITER_CEILING=200 with 250 Reads halts on iteration_count.
#   T-LCB-7  Backward compat — high LOOP_BREAKER_ITER_CEILING (100000) does NOT prevent per-class halts.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"/../../.. && pwd)"
PRE_HOOK="$REPO_ROOT/core/loop-circuit-breaker/hooks/pretooluse-count-hash.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

setup_env() {
  # Reset HOME/telemetry per test to keep counters fresh.
  local sub="$1"
  TEST_HOME="$TMP/$sub"
  mkdir -p "$TEST_HOME/.claude"
  export HOME="$TEST_HOME"
  export GOVERNANCE_PACK_TELEMETRY_FILE="$TEST_HOME/.claude/telemetry.jsonl"
  unset LOOP_BREAKER_READ_CEILING LOOP_BREAKER_WRITE_CEILING LOOP_BREAKER_ITER_CEILING
  export LOOP_BREAKER_USD_CEILING=1000000.0
}

fire_call() {
  local tool="$1" idx="$2" sess="$3"
  local fp_field='"file_path":"/tmp/'"$tool"'-'"$idx"'.txt"'
  local payload
  payload=$(printf '{"tool_name":"%s","session_id":"%s","tool_input":{%s}}' "$tool" "$sess" "$fp_field")
  printf '%s' "$payload" | bash "$PRE_HOOK" >/dev/null 2>/dev/null
}

# Avoid hash-collision halt by varying tool_input file_path each call (the canonical hash
# includes the path so 200 distinct paths produce 200 distinct hashes).

fail=0

# --- T-LCB-1: 200 Read calls under default ceilings → no halt --------------
setup_env "t1"
SESSION="t1-reads"
for i in $(seq 1 200); do
  if ! fire_call "Read" "$i" "$SESSION"; then
    printf 'FAIL: T-LCB-1 Read call %s halted unexpectedly under default ceilings\n' "$i" >&2
    fail=1
    break
  fi
done
if [ "$fail" -eq 0 ]; then
  printf 'PASS: T-LCB-1 200 Reads under default ceilings (read=600) do not halt\n'
fi

# --- T-LCB-2: 101 Reads with LOOP_BREAKER_READ_CEILING=100 → halt on read_count ---
setup_env "t2"
export LOOP_BREAKER_READ_CEILING=100
SESSION="t2-reads"
halted=0
for i in $(seq 1 101); do
  if ! fire_call "Read" "$i" "$SESSION"; then
    if [ "$i" -eq 101 ]; then
      halted=1
    else
      printf 'FAIL: T-LCB-2 Read call %s halted but expected halt on call 101\n' "$i" >&2
      fail=1
    fi
    break
  fi
done
if [ "$halted" -eq 1 ]; then
  printf 'PASS: T-LCB-2 101st Read halts (read_ceiling=100)\n'
elif [ "$fail" -eq 0 ]; then
  printf 'FAIL: T-LCB-2 expected halt at call 101 (read_ceiling=100); never halted\n' >&2
  fail=1
fi
unset LOOP_BREAKER_READ_CEILING

# --- T-LCB-3: 151 Edit calls under default ceilings → halt on write_count --
setup_env "t3"
SESSION="t3-edits"
halted=0
for i in $(seq 1 151); do
  if ! fire_call "Edit" "$i" "$SESSION"; then
    if [ "$i" -eq 151 ]; then
      halted=1
    else
      printf 'FAIL: T-LCB-3 Edit call %s halted but expected halt on call 151\n' "$i" >&2
      fail=1
    fi
    break
  fi
done
if [ "$halted" -eq 1 ]; then
  printf 'PASS: T-LCB-3 151st Edit halts (write_ceiling=150)\n'
elif [ "$fail" -eq 0 ]; then
  printf 'FAIL: T-LCB-3 expected halt at Edit call 151; never halted\n' >&2
  fail=1
fi

# --- T-LCB-4: 100 Read + 100 Edit (mixed, both under ceilings) → no halt ---
setup_env "t4"
SESSION="t4-mixed"
mixed_failed=0
for i in $(seq 1 100); do
  if ! fire_call "Read" "$i" "$SESSION"; then
    printf 'FAIL: T-LCB-4 Read call %s halted unexpectedly\n' "$i" >&2
    mixed_failed=1
    break
  fi
done
if [ "$mixed_failed" -eq 0 ]; then
  for i in $(seq 1 100); do
    if ! fire_call "Edit" "$i" "$SESSION"; then
      printf 'FAIL: T-LCB-4 Edit call %s halted unexpectedly\n' "$i" >&2
      mixed_failed=1
      break
    fi
  done
fi
if [ "$mixed_failed" -eq 0 ]; then
  printf 'PASS: T-LCB-4 100 Read + 100 Edit (under per-class ceilings) do not halt\n'
else
  fail=1
fi

# --- T-LCB-5: 100 Read + 151 Edit → halt on Edit 151 (write_count) ---------
setup_env "t5"
SESSION="t5-mixed-overflow"
m5_fail=0
for i in $(seq 1 100); do
  if ! fire_call "Read" "$i" "$SESSION"; then
    printf 'FAIL: T-LCB-5 Read call %s halted unexpectedly\n' "$i" >&2
    m5_fail=1
    break
  fi
done
if [ "$m5_fail" -eq 0 ]; then
  m5_halted=0
  for i in $(seq 1 151); do
    if ! fire_call "Edit" "$i" "$SESSION"; then
      if [ "$i" -eq 151 ]; then
        m5_halted=1
      else
        printf 'FAIL: T-LCB-5 Edit call %s halted before expected\n' "$i" >&2
        m5_fail=1
      fi
      break
    fi
  done
  if [ "$m5_halted" -eq 1 ]; then
    # Confirm halt was write_count, not read_count or iteration_count, by inspecting telemetry.
    last_halt="$(grep '"action":"halt"' "$GOVERNANCE_PACK_TELEMETRY_FILE" 2>/dev/null | tail -n1)"
    if printf '%s' "$last_halt" | grep -q '"counter":"write_count"'; then
      printf 'PASS: T-LCB-5 mixed 100R+151E halts on write_count\n'
    else
      printf 'FAIL: T-LCB-5 expected halt counter=write_count; got=%s\n' "$last_halt" >&2
      m5_fail=1
    fi
  elif [ "$m5_fail" -eq 0 ]; then
    printf 'FAIL: T-LCB-5 expected halt at Edit 151; never halted\n' >&2
    m5_fail=1
  fi
fi
[ "$m5_fail" -ne 0 ] && fail=1

# --- T-LCB-6: backward compat — LOOP_BREAKER_ITER_CEILING=200 + 250 Reads halts ---
setup_env "t6"
export LOOP_BREAKER_ITER_CEILING=200
SESSION="t6-iter-cap"
m6_halted=0
for i in $(seq 1 250); do
  if ! fire_call "Read" "$i" "$SESSION"; then
    if [ "$i" -eq 201 ]; then
      m6_halted=1
    else
      printf 'FAIL: T-LCB-6 Read call %s halted but expected halt on call 201 (iter_ceiling=200)\n' "$i" >&2
      fail=1
    fi
    break
  fi
done
if [ "$m6_halted" -eq 1 ]; then
  last_halt="$(grep '"action":"halt"' "$GOVERNANCE_PACK_TELEMETRY_FILE" 2>/dev/null | tail -n1)"
  if printf '%s' "$last_halt" | grep -q '"counter":"iteration_count"'; then
    printf 'PASS: T-LCB-6 LOOP_BREAKER_ITER_CEILING=200 halts on iteration_count at call 201\n'
  else
    printf 'FAIL: T-LCB-6 expected halt counter=iteration_count; got=%s\n' "$last_halt" >&2
    fail=1
  fi
fi
unset LOOP_BREAKER_ITER_CEILING

# --- T-LCB-7: backward compat — high ITER_CEILING preserves per-class halt -
setup_env "t7"
export LOOP_BREAKER_ITER_CEILING=100000
SESSION="t7-high-iter"
m7_halted=0
for i in $(seq 1 151); do
  if ! fire_call "Edit" "$i" "$SESSION"; then
    if [ "$i" -eq 151 ]; then
      m7_halted=1
    else
      printf 'FAIL: T-LCB-7 Edit call %s halted before expected\n' "$i" >&2
      fail=1
    fi
    break
  fi
done
if [ "$m7_halted" -eq 1 ]; then
  last_halt="$(grep '"action":"halt"' "$GOVERNANCE_PACK_TELEMETRY_FILE" 2>/dev/null | tail -n1)"
  if printf '%s' "$last_halt" | grep -q '"counter":"write_count"'; then
    printf 'PASS: T-LCB-7 LOOP_BREAKER_ITER_CEILING=100000 still halts on write_count at Edit 151\n'
  else
    printf 'FAIL: T-LCB-7 expected halt counter=write_count; got=%s\n' "$last_halt" >&2
    fail=1
  fi
fi
unset LOOP_BREAKER_ITER_CEILING

if [ "$fail" -eq 0 ]; then
  printf 'test-tool-class-counters: PASS (7/7)\n'
fi
exit "$fail"
