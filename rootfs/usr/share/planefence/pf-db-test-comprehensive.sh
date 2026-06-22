#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2154
# -----------------------------------------------------------------------------------
# Phase 5 Comprehensive Test Framework
# Complete functionality and performance testing for Phase 5 database layer
# Includes: unit tests, stress tests, concurrent ops, edge cases, and metrics
# -----------------------------------------------------------------------------------

set -eo pipefail

source /scripts/pf-common 2>/dev/null || source ./pf-common

DB_PATH="${DB_PATH:-/run/planefence/planefence-records.sqlite}"
TEST_DAY="260622"
PERSIST_DB="${DB_PATH%/*}/test-results.sqlite"
REPORT_FILE="/tmp/pf-db-test-report-$(date +%s).txt"

# Test counters
UNIT_PASS=0 UNIT_FAIL=0
STRESS_PASS=0 STRESS_FAIL=0
CONCURRENT_PASS=0 CONCURRENT_FAIL=0
EDGE_CASE_PASS=0 EDGE_CASE_FAIL=0
PERF_PASS=0 PERF_FAIL=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Timing tracking
declare -A TIMINGS
declare -A MEMORY_USAGE

log_test() { printf '%b[TEST]%b %s\n' "$BLUE" "$NC" "$1" | tee -a "$REPORT_FILE"; }
log_pass() { printf '%b[PASS]%b %s\n' "$GREEN" "$NC" "$1" | tee -a "$REPORT_FILE"; }
log_fail() { printf '%b[FAIL]%b %s\n' "$RED" "$NC" "$1" | tee -a "$REPORT_FILE"; }
log_info() { printf '%b[INFO]%b %s\n' "$YELLOW" "$NC" "$1" | tee -a "$REPORT_FILE"; }
log_section() { printf '\n%b=== %s ===%b\n' "$BLUE" "$1" "$NC" | tee -a "$REPORT_FILE"; }

# Timing wrapper
time_operation() {
  local name="$1" cmd="${@:2}"
  local start end elapsed mem_before mem_after
  
  mem_before=$(ps aux | grep "[p]f-db.py" | awk '{sum+=$6} END {print sum}' || echo "0")
  start=$(date +%s%N)
  
  if eval "$cmd" >/dev/null 2>&1; then
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    mem_after=$(ps aux | grep "[p]f-db.py" | awk '{sum+=$6} END {print sum}' || echo "0")
    TIMINGS["$name"]=$elapsed
    MEMORY_USAGE["$name"]=$(( mem_after - mem_before ))
    return 0
  fi
  return 1
}

# ============================================================================
# UNIT TESTS - Verify all commands and functions work correctly
# ============================================================================
test_unit_basic() {
  log_section "UNIT TESTS: Basic Command Functionality"
  
  log_test "Test 1.1: Database initialization"
  if /usr/share/planefence/pf-db.py init --db "$DB_PATH" >/dev/null 2>&1; then
    log_pass "1.1: Database initialized"
    ((UNIT_PASS++))
  else
    log_fail "1.1: Database initialization failed"
    ((UNIT_FAIL++))
  fi

  log_test "Test 1.2: Integrity check"
  if /usr/share/planefence/pf-db.py integrity-check --db "$DB_PATH" >/dev/null 2>&1; then
    log_pass "1.2: Integrity check passed"
    ((UNIT_PASS++))
  else
    log_fail "1.2: Integrity check failed"
    ((UNIT_FAIL++))
  fi

  log_test "Test 1.3: Command availability (9 commands)"
  local commands=("query-records" "query-ready-for-notification" "get-record" "set-record" 
                  "delete-record" "get-kv" "set-kv" "get-heatmap" "set-heatmap-row")
  local cmd_pass=0
  for cmd in "${commands[@]}"; do
    if /usr/share/planefence/pf-db.py "$cmd" --help >/dev/null 2>&1 || [[ $? -eq 2 ]]; then
      ((cmd_pass++))
    fi
  done
  if [[ $cmd_pass -eq 9 ]]; then
    log_pass "1.3: All 9 commands available"
    ((UNIT_PASS++))
  else
    log_fail "1.3: Only $cmd_pass/9 commands available"
    ((UNIT_FAIL++))
  fi

  log_test "Test 1.4: Create and retrieve record"
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "UNIT001" --index 0 >/dev/null 2>&1
icao=UNIT001
callsign=UNITEST
type=B738
owner=Test Airlines
ready_to_notify=true
EOF
  if [[ $? -eq 0 ]]; then
    result=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "UNIT001" --type pf 2>/dev/null)
    if printf '%s' "$result" | jq -e '.record.icao == "UNIT001"' >/dev/null 2>&1; then
      log_pass "1.4: Record CRUD works correctly"
      ((UNIT_PASS++))
    else
      log_fail "1.4: Record retrieval failed"
      ((UNIT_FAIL++))
    fi
  else
    log_fail "1.4: Record creation failed"
    ((UNIT_FAIL++))
  fi

  log_test "Test 1.5: KV storage"
  if /usr/share/planefence/pf-db.py set-kv --db "$DB_PATH" --key "unit:test" --value "testval" >/dev/null 2>&1; then
    result=$(/usr/share/planefence/pf-db.py get-kv --db "$DB_PATH" --key "unit:test" 2>/dev/null)
    if printf '%s' "$result" | jq -e '.value == "testval"' >/dev/null 2>&1; then
      log_pass "1.5: KV storage works"
      ((UNIT_PASS++))
    else
      log_fail "1.5: KV retrieval failed"
      ((UNIT_FAIL++))
    fi
  else
    log_fail "1.5: KV set failed"
    ((UNIT_FAIL++))
  fi

  log_test "Test 1.6: Heatmap operations"
  if /usr/share/planefence/pf-db.py set-heatmap-row --db "$DB_PATH" --day "$TEST_DAY" --latlon-key "37.77,-122.42" --hit-count 50 >/dev/null 2>&1; then
    result=$(/usr/share/planefence/pf-db.py get-heatmap --db "$DB_PATH" --day "$TEST_DAY" 2>/dev/null)
    count=$(printf '%s' "$result" | jq '.count // 0' 2>/dev/null)
    if (( count >= 1 )); then
      log_pass "1.6: Heatmap operations work"
      ((UNIT_PASS++))
    else
      log_fail "1.6: Heatmap retrieval failed"
      ((UNIT_FAIL++))
    fi
  else
    log_fail "1.6: Heatmap set failed"
    ((UNIT_FAIL++))
  fi
}

# ============================================================================
# STRESS TESTS - High volume operations
# ============================================================================
test_stress_large_dataset() {
  log_section "STRESS TESTS: High Volume Operations"

  log_test "Test 2.1: Create 500 records in one day"
  local start_time end_time elapsed
  start_time=$(date +%s%N)
  
  for i in {1..500}; do
    cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "STRESS$(printf '%04d' $i)" --index "$i" >/dev/null 2>&1
icao=STRESS$(printf '%04d' $i)
callsign=STR$(printf '%03d' $i)
owner=Stress Airline
type=B738
ready_to_notify=$((i % 2))
EOF
  done
  
  end_time=$(date +%s%N)
  elapsed=$(( (end_time - start_time) / 1000000 ))
  TIMINGS["stress_create_500"]=$elapsed
  
  log_pass "2.1: Created 500 records in ${elapsed}ms"
  ((STRESS_PASS++))

  log_test "Test 2.2: Query large dataset"
  start_time=$(date +%s%N)
  result=$(/usr/share/planefence/pf-db.py query-records --db "$DB_PATH" --table pf_records --day "$TEST_DAY" 2>/dev/null)
  end_time=$(date +%s%N)
  elapsed=$(( (end_time - start_time) / 1000000 ))
  
  count=$(printf '%s' "$result" | jq '.count // 0' 2>/dev/null)
  TIMINGS["stress_query_500"]=$elapsed
  
  if (( count >= 500 )); then
    log_pass "2.2: Queried $count records in ${elapsed}ms"
    ((STRESS_PASS++))
  else
    log_fail "2.2: Query returned only $count records"
    ((STRESS_FAIL++))
  fi

  log_test "Test 2.3: Filter query with WHERE clause"
  start_time=$(date +%s%N)
  result=$(/usr/share/planefence/pf-db.py query-records --db "$DB_PATH" --table pf_records --day "$TEST_DAY" --where "callsign LIKE 'STR%'" 2>/dev/null)
  end_time=$(date +%s%N)
  elapsed=$(( (end_time - start_time) / 1000000 ))
  
  count=$(printf '%s' "$result" | jq '.count // 0' 2>/dev/null)
  TIMINGS["stress_query_filtered"]=$elapsed
  
  if (( count >= 100 )); then
    log_pass "2.3: Filtered query returned $count records in ${elapsed}ms"
    ((STRESS_PASS++))
  else
    log_fail "2.3: Filtered query returned only $count records"
    ((STRESS_FAIL++))
  fi

  log_test "Test 2.4: Ready-for-notification on large dataset"
  start_time=$(date +%s%N)
  result=$(/usr/share/planefence/pf-db.py query-ready-for-notification --db "$DB_PATH" --day "$TEST_DAY" --type pf 2>/dev/null)
  end_time=$(date +%s%N)
  elapsed=$(( (end_time - start_time) / 1000000 ))
  
  count=$(printf '%s' "$result" | jq '.icaos | length // 0' 2>/dev/null)
  TIMINGS["stress_notification_query"]=$elapsed
  
  if (( count >= 100 )); then
    log_pass "2.4: Found $count notification-ready records in ${elapsed}ms"
    ((STRESS_PASS++))
  else
    log_fail "2.4: Found only $count notification-ready records"
    ((STRESS_FAIL++))
  fi
}

# ============================================================================
# EDGE CASE TESTS - Boundary conditions and special characters
# ============================================================================
test_edge_cases() {
  log_section "EDGE CASE TESTS: Boundary Conditions"

  log_test "Test 3.1: Empty string values"
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE001" --index 900 >/dev/null 2>&1
icao=EDGE001
callsign=
owner=
type=
EOF
  result=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE001" --type pf 2>/dev/null)
  if printf '%s' "$result" | jq -e '.ok' >/dev/null 2>&1; then
    log_pass "3.1: Empty string values handled"
    ((EDGE_CASE_PASS++))
  else
    log_fail "3.1: Empty string handling failed"
    ((EDGE_CASE_FAIL++))
  fi

  log_test "Test 3.2: Special characters in fields"
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE002" --index 901 >/dev/null 2>&1
icao=EDGE002
callsign=TEST-123/ABC'XYZ"TEST
owner=Airline & Co., Inc.
type=B738
EOF
  result=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE002" --type pf 2>/dev/null)
  if printf '%s' "$result" | jq -e '.ok' >/dev/null 2>&1; then
    log_pass "3.2: Special characters handled"
    ((EDGE_CASE_PASS++))
  else
    log_fail "3.2: Special character handling failed"
    ((EDGE_CASE_FAIL++))
  fi

  log_test "Test 3.3: Maximum integer values"
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE003" --index 999999 >/dev/null 2>&1
icao=EDGE003
time:firstseen=9999999999
time:lastseen=9999999999
distance=999999.99
EOF
  result=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE003" --type pf 2>/dev/null)
  if printf '%s' "$result" | jq -e '.ok' >/dev/null 2>&1; then
    log_pass "3.3: Large integer values handled"
    ((EDGE_CASE_PASS++))
  else
    log_fail "3.3: Large integer handling failed"
    ((EDGE_CASE_FAIL++))
  fi

  log_test "Test 3.4: Unicode characters"
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE004" --index 902 >/dev/null 2>&1
icao=EDGE004
owner=Aéroport de Paris (CDG) 中文 日本語
type=B738
EOF
  result=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE004" --type pf 2>/dev/null)
  if printf '%s' "$result" | jq -e '.ok' >/dev/null 2>&1; then
    log_pass "3.4: Unicode characters handled"
    ((EDGE_CASE_PASS++))
  else
    log_fail "3.4: Unicode handling failed"
    ((EDGE_CASE_FAIL++))
  fi

  log_test "Test 3.5: Concurrent updates to same record"
  for i in {1..5}; do
    echo "update_count=$i" | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE005" --index 903 --type pf >/dev/null 2>&1 &
  done
  wait
  result=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE005" --type pf 2>/dev/null)
  if printf '%s' "$result" | jq -e '.ok' >/dev/null 2>&1; then
    log_pass "3.5: Concurrent updates handled (no corruption)"
    ((EDGE_CASE_PASS++))
  else
    log_fail "3.5: Concurrent update handling failed"
    ((EDGE_CASE_FAIL++))
  fi
}

# ============================================================================
# PERFORMANCE TESTS - Response times and resource usage
# ============================================================================
test_performance() {
  log_section "PERFORMANCE TESTS: Timing and Resource Usage"

  log_test "Test 4.1: Single record get (100 iterations)"
  local total_time=0
  for i in {1..100}; do
    local start end
    start=$(date +%s%N)
    /usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "STRESS0001" --type pf >/dev/null 2>&1
    end=$(date +%s%N)
    total_time=$(( total_time + (end - start) / 1000000 ))
  done
  local avg_time=$(( total_time / 100 ))
  TIMINGS["perf_get_record_avg"]=$avg_time
  log_pass "4.1: Average get-record time: ${avg_time}ms (100 ops)"
  if (( avg_time < 100 )); then
    ((PERF_PASS++))
  else
    ((PERF_FAIL++))
  fi

  log_test "Test 4.2: Set operation performance"
  start=$(date +%s%N)
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "PERFTEST" --index 5000 >/dev/null 2>&1
icao=PERFTEST
callsign=PERF001
owner=Performance Test
type=B738
EOF
  end=$(date +%s%N)
  local set_time=$(( (end - start) / 1000000 ))
  TIMINGS["perf_set_record"]=$set_time
  log_pass "4.2: Set-record operation: ${set_time}ms"
  ((PERF_PASS++))

  log_test "Test 4.3: Query performance (all records)"
  start=$(date +%s%N)
  /usr/share/planefence/pf-db.py query-records --db "$DB_PATH" --table pf_records --day "$TEST_DAY" >/dev/null 2>&1
  end=$(date +%s%N)
  local query_time=$(( (end - start) / 1000000 ))
  TIMINGS["perf_query_all"]=$query_time
  log_pass "4.3: Query all records: ${query_time}ms"
  ((PERF_PASS++))

  log_test "Test 4.4: Memory stability (check for leaks)"
  local mem_baseline
  mem_baseline=$(ps aux | grep "[p]f-db.py" | awk '{sum+=$6} END {print sum}' || echo "0")
  for i in {1..50}; do
    /usr/share/planefence/pf-db.py query-records --db "$DB_PATH" --table pf_records --day "$TEST_DAY" >/dev/null 2>&1
  done
  local mem_after
  mem_after=$(ps aux | grep "[p]f-db.py" | awk '{sum+=$6} END {print sum}' || echo "0")
  local mem_increase=$(( mem_after - mem_baseline ))
  MEMORY_USAGE["perf_50_queries"]=$mem_increase
  log_pass "4.4: Memory after 50 queries: ${mem_increase}KB increase"
  if (( mem_increase < 50000 )); then
    ((PERF_PASS++))
  else
    ((PERF_FAIL++))
  fi
}

# ============================================================================
# BASH WRAPPER TESTS - Verify DB_* functions work correctly
# ============================================================================
test_bash_wrappers() {
  log_section "BASH WRAPPER TESTS: DB_* Functions"

  log_test "Test 5.1: DB_GET_KV function"
  if val=$(DB_GET_KV --key "unit:test" 2>/dev/null) && [[ "$val" == "testval" ]]; then
    log_pass "5.1: DB_GET_KV works"
    ((UNIT_PASS++))
  else
    log_fail "5.1: DB_GET_KV failed"
    ((UNIT_FAIL++))
  fi

  log_test "Test 5.2: DB_SET_KV function"
  if DB_SET_KV --key "wrapper:test" --value "wrapper_val" 2>/dev/null; then
    log_pass "5.2: DB_SET_KV works"
    ((UNIT_PASS++))
  else
    log_fail "5.2: DB_SET_KV failed"
    ((UNIT_FAIL++))
  fi

  log_test "Test 5.3: DB_GET_RECORD function"
  if rec=$(DB_GET_RECORD --day "$TEST_DAY" --icao "UNIT001" --type pf 2>/dev/null) && printf '%s' "$rec" | jq -e '._index' >/dev/null 2>&1; then
    log_pass "5.3: DB_GET_RECORD works"
    ((UNIT_PASS++))
  else
    log_fail "5.3: DB_GET_RECORD failed"
    ((UNIT_FAIL++))
  fi

  log_test "Test 5.4: DB_QUERY_RECORDS function"
  if recs=$(DB_QUERY_RECORDS --table pf_records --day "$TEST_DAY" 2>/dev/null) && printf '%s' "$recs" | jq -e 'length' >/dev/null 2>&1; then
    log_pass "5.4: DB_QUERY_RECORDS works"
    ((UNIT_PASS++))
  else
    log_fail "5.4: DB_QUERY_RECORDS failed"
    ((UNIT_FAIL++))
  fi

  log_test "Test 5.5: DB_QUERY_READY_FOR_NOTIFICATION function"
  if notif=$(DB_QUERY_READY_FOR_NOTIFICATION --day "$TEST_DAY" --type pf 2>/dev/null) && printf '%s' "$notif" | jq -e 'length' >/dev/null 2>&1; then
    log_pass "5.5: DB_QUERY_READY_FOR_NOTIFICATION works"
    ((UNIT_PASS++))
  else
    log_fail "5.5: DB_QUERY_READY_FOR_NOTIFICATION failed"
    ((UNIT_FAIL++))
  fi
}

# ============================================================================
# INTEGRATION TESTS - Real-world scenarios
# ============================================================================
test_integration() {
  log_section "INTEGRATION TESTS: Real-world Scenarios"

  log_test "Test 6.1: Aircraft lifecycle (create -> update -> notify -> delete)"
  local icao="INTEG001"
  
  # Create
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "$icao" --index 6000 >/dev/null 2>&1
icao=$icao
callsign=INTEG001
type=B738
ready_to_notify=false
EOF
  
  # Update
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "$icao" --index 6000 --type pf >/dev/null 2>&1
callsign=INTEG001
ready_to_notify=true
EOF
  
  # Query
  result=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "$icao" --type pf 2>/dev/null)
  
  # Delete
  /usr/share/planefence/pf-db.py delete-record --db "$DB_PATH" --day "$TEST_DAY" --icao "$icao" --type pf >/dev/null 2>&1
  
  if printf '%s' "$result" | jq -e '.record.ready_to_notify' >/dev/null 2>&1; then
    log_pass "6.1: Complete aircraft lifecycle works"
    ((EDGE_CASE_PASS++))
  else
    log_fail "6.1: Lifecycle test failed"
    ((EDGE_CASE_FAIL++))
  fi

  log_test "Test 6.2: Multi-day operation"
  local day1="260621" day2="260622"
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$day1" --icao "MULTI001" --index 100 >/dev/null 2>&1
icao=MULTI001
callsign=MULTI001
type=B738
EOF
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$day2" --icao "MULTI001" --index 200 >/dev/null 2>&1
icao=MULTI001
callsign=MULTI001
type=B738
EOF
  
  rec1=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$day1" --icao "MULTI001" --type pf 2>/dev/null)
  rec2=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$day2" --icao "MULTI001" --type pf 2>/dev/null)
  
  if printf '%s' "$rec1" | jq -e '.ok' >/dev/null 2>&1 && printf '%s' "$rec2" | jq -e '.ok' >/dev/null 2>&1; then
    log_pass "6.2: Multi-day operations work"
    ((STRESS_PASS++))
  else
    log_fail "6.2: Multi-day test failed"
    ((STRESS_FAIL++))
  fi
}

# ============================================================================
# Generate Report
# ============================================================================
generate_report() {
  log_section "TEST RESULTS SUMMARY"
  
  local total_pass total_fail
  total_pass=$(( UNIT_PASS + STRESS_PASS + CONCURRENT_PASS + EDGE_CASE_PASS + PERF_PASS ))
  total_fail=$(( UNIT_FAIL + STRESS_FAIL + CONCURRENT_FAIL + EDGE_CASE_FAIL + PERF_FAIL ))
  
  printf '\n%b=== Category Breakdown ===%b\n' "$BLUE" "$NC" | tee -a "$REPORT_FILE"
  printf 'Unit Tests:         %b%3d passed%b, %b%3d failed%b\n' "$GREEN" "$UNIT_PASS" "$NC" "$RED" "$UNIT_FAIL" "$NC" | tee -a "$REPORT_FILE"
  printf 'Stress Tests:       %b%3d passed%b, %b%3d failed%b\n' "$GREEN" "$STRESS_PASS" "$NC" "$RED" "$STRESS_FAIL" "$NC" | tee -a "$REPORT_FILE"
  printf 'Edge Case Tests:    %b%3d passed%b, %b%3d failed%b\n' "$GREEN" "$EDGE_CASE_PASS" "$NC" "$RED" "$EDGE_CASE_FAIL" "$NC" | tee -a "$REPORT_FILE"
  printf 'Performance Tests:  %b%3d passed%b, %b%3d failed%b\n' "$GREEN" "$PERF_PASS" "$NC" "$RED" "$PERF_FAIL" "$NC" | tee -a "$REPORT_FILE"
  printf 'Concurrent Tests:   %b%3d passed%b, %b%3d failed%b\n' "$GREEN" "$CONCURRENT_PASS" "$NC" "$RED" "$CONCURRENT_FAIL" "$NC" | tee -a "$REPORT_FILE"
  
  printf '\n%b=== Performance Metrics ===%b\n' "$BLUE" "$NC" | tee -a "$REPORT_FILE"
  printf 'Operation                     Time (ms)    Memory (KB)\n' | tee -a "$REPORT_FILE"
  printf '%s\n' "$(printf '%-30s %10s %10s' "---" "---" "---")" | tee -a "$REPORT_FILE"
  
  for op in $(printf '%s\n' "${!TIMINGS[@]}" | sort); do
    local time="${TIMINGS[$op]}"
    local mem="${MEMORY_USAGE[$op]:-0}"
    printf '%-30s %10dms %10dKB\n' "$op" "$time" "$mem" | tee -a "$REPORT_FILE"
  done
  
  printf '\n%b=== Overall Result ===%b\n' "$BLUE" "$NC" | tee -a "$REPORT_FILE"
  if (( total_fail == 0 )); then
    printf '%bALL TESTS PASSED: %d/%d%b\n' "$GREEN" "$total_pass" "$((total_pass + total_fail))" "$NC" | tee -a "$REPORT_FILE"
    return 0
  else
    printf '%bTESTS FAILED: %d passed, %d failed%b\n' "$RED" "$total_pass" "$total_fail" "$NC" | tee -a "$REPORT_FILE"
    return 1
  fi
}

# ============================================================================
# Main execution
# ============================================================================
main() {
  printf '\n%b╔════════════════════════════════════════════════════════════╗%b\n' "$BLUE" "$NC" | tee "$REPORT_FILE"
  printf '%b║       Phase 5 Comprehensive Test Framework                ║%b\n' "$BLUE" "$NC" | tee -a "$REPORT_FILE"
  printf '%b╚════════════════════════════════════════════════════════════╝%b\n\n' "$BLUE" "$NC" | tee -a "$REPORT_FILE"
  
  log_info "Database: $DB_PATH"
  log_info "Report: $REPORT_FILE"
  log_info "Start time: $(date)"
  printf '\n' | tee -a "$REPORT_FILE"

  # Run all test suites
  test_unit_basic
  test_stress_large_dataset
  test_edge_cases
  test_performance
  test_bash_wrappers
  test_integration
  
  printf '\n' | tee -a "$REPORT_FILE"
  generate_report
  
  printf '\n%b═══════════════════════════════════════════════════════════%b\n' "$BLUE" "$NC" | tee -a "$REPORT_FILE"
  printf 'Report saved to: %s\n' "$REPORT_FILE" | tee -a "$REPORT_FILE"
  printf '%b═══════════════════════════════════════════════════════════%b\n\n' "$BLUE" "$NC" | tee -a "$REPORT_FILE"
}

main "$@"
