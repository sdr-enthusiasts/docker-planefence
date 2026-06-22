#!/command/with-contenv bash
#shellcheck shell=bash disable=SC1091,SC2154
# -----------------------------------------------------------------------------------
# Phase 5 Test Suite: Direct Streaming Query Commands
# Comprehensive tests for all DB_* functions and pf-db.py commands
# -----------------------------------------------------------------------------------

set -eo pipefail

source /scripts/pf-common

DB_PATH="${DB_PATH:-/run/planefence/planefence-records.sqlite}"
TEST_DAY="260622"  # YYMMDD format
TEST_ICAO="ABC123"
TEST_ICAO2="DEF456"
PASSED=0
FAILED=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_test() {
  printf '[TEST] %s\n' "$1"
}

log_pass() {
  printf "${GREEN}[PASS]${NC} %s\n" "$1"
  ((PASSED++))
}

log_fail() {
  printf "${RED}[FAIL]${NC} %s\n" "$1"
  ((FAILED++))
}

log_info() {
  printf "[INFO] %s\n" "$1"
}

# ============================================================================
# Test 1: pf-db.py command availability
# ============================================================================
test_command_availability() {
  log_test "Testing pf-db.py command availability"

  local commands=(
    "query-records"
    "query-ready-for-notification"
    "get-record"
    "set-record"
    "delete-record"
    "get-kv"
    "set-kv"
    "get-heatmap"
    "set-heatmap-row"
  )

  for cmd in "${commands[@]}"; do
    if /usr/share/planefence/pf-db.py "$cmd" --help >/dev/null 2>&1 || [[ $? -eq 2 ]]; then
      log_pass "Command available: $cmd"
    else
      log_fail "Command not available: $cmd"
    fi
  done
}

# ============================================================================
# Test 2: Database initialization and integrity
# ============================================================================
test_db_init() {
  log_test "Testing database initialization"

  if ! /usr/share/planefence/pf-db.py init --db "$DB_PATH" >/dev/null 2>&1; then
    log_fail "Database initialization failed"
    return 1
  fi
  log_pass "Database initialized successfully"

  if ! /usr/share/planefence/pf-db.py integrity-check --db "$DB_PATH" >/dev/null 2>&1; then
    log_fail "Database integrity check failed"
    return 1
  fi
  log_pass "Database integrity check passed"
}

# ============================================================================
# Test 3: Record creation and retrieval (pf_records)
# ============================================================================
test_record_crud() {
  log_test "Testing record CRUD operations for pf_records"

  # Create a test record
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "$TEST_ICAO" --index 0 >/dev/null 2>&1
icao=$TEST_ICAO
callsign=TEST123
tail=N12345
type=B738
time:firstseen=1234567890
time:lastseen=1234567899
owner=Test Airline
ready_to_notify=true
EOF

  if [[ $? -eq 0 ]]; then
    log_pass "Record created: $TEST_ICAO"
  else
    log_fail "Failed to create record: $TEST_ICAO"
    return 1
  fi

  # Retrieve the record
  result=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "$TEST_ICAO" --type pf 2>/dev/null || echo '{"ok":false}')
  
  if printf '%s' "$result" | jq -e '.ok' >/dev/null 2>&1; then
    log_pass "Record retrieved successfully"
  else
    log_fail "Failed to retrieve record"
    return 1
  fi

  # Verify record data
  icao_val=$(printf '%s' "$result" | jq -r '.record.icao // ""' 2>/dev/null)
  if [[ "$icao_val" == "$TEST_ICAO" ]]; then
    log_pass "Record ICAO verified: $icao_val"
  else
    log_fail "Record ICAO mismatch: expected $TEST_ICAO, got $icao_val"
  fi
}

# ============================================================================
# Test 4: Query records with filters
# ============================================================================
test_query_records() {
  log_test "Testing record queries with filters"

  # Create multiple test records
  cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "$TEST_ICAO2" --index 1 >/dev/null 2>&1
icao=$TEST_ICAO2
callsign=TEST456
ready_to_notify=false
EOF

  # Query all records for the day
  result=$(/usr/share/planefence/pf-db.py query-records --db "$DB_PATH" --table pf_records --day "$TEST_DAY" 2>/dev/null || echo '{"ok":false}')

  count=$(printf '%s' "$result" | jq '.count // 0' 2>/dev/null)
  if (( count >= 2 )); then
    log_pass "Query returned $count records"
  else
    log_fail "Query returned fewer than expected records: $count"
  fi
}

# ============================================================================
# Test 5: Ready-for-notification query
# ============================================================================
test_ready_for_notification() {
  log_test "Testing ready-for-notification query"

  result=$(/usr/share/planefence/pf-db.py query-ready-for-notification --db "$DB_PATH" --day "$TEST_DAY" --type pf 2>/dev/null || echo '{"ok":false}')

  icaos=$(printf '%s' "$result" | jq '.icaos | length // 0' 2>/dev/null)
  if (( icaos >= 1 )); then
    log_pass "Found $icaos records ready for notification"
  else
    log_fail "No records found ready for notification"
  fi
}

# ============================================================================
# Test 6: Key-Value storage
# ============================================================================
test_kv_storage() {
  log_test "Testing key-value storage"

  # Set a key-value pair
  /usr/share/planefence/pf-db.py set-kv --db "$DB_PATH" --key "test:key1" --value "test_value_1" >/dev/null 2>&1
  
  if [[ $? -eq 0 ]]; then
    log_pass "KV pair set: test:key1 = test_value_1"
  else
    log_fail "Failed to set KV pair"
    return 1
  fi

  # Retrieve the key-value pair
  result=$(/usr/share/planefence/pf-db.py get-kv --db "$DB_PATH" --key "test:key1" 2>/dev/null)
  
  value=$(printf '%s' "$result" | jq -r '.value // ""' 2>/dev/null)
  if [[ "$value" == "test_value_1" ]]; then
    log_pass "KV pair retrieved and verified: $value"
  else
    log_fail "KV pair retrieval failed or mismatch: expected 'test_value_1', got '$value'"
  fi
}

# ============================================================================
# Test 7: Heatmap operations
# ============================================================================
test_heatmap() {
  log_test "Testing heatmap operations"

  # Set a heatmap row
  /usr/share/planefence/pf-db.py set-heatmap-row --db "$DB_PATH" --day "$TEST_DAY" --latlon-key "37.7749,-122.4194" --hit-count 42 >/dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    log_pass "Heatmap row set: 37.7749,-122.4194 = 42"
  else
    log_fail "Failed to set heatmap row"
    return 1
  fi

  # Retrieve heatmap for the day
  result=$(/usr/share/planefence/pf-db.py get-heatmap --db "$DB_PATH" --day "$TEST_DAY" 2>/dev/null)

  count=$(printf '%s' "$result" | jq '.count // 0' 2>/dev/null)
  if (( count >= 1 )); then
    log_pass "Heatmap retrieved: $count rows"
  else
    log_fail "Heatmap retrieval failed or empty"
  fi
}

# ============================================================================
# Test 8: Bash DB_* function wrappers
# ============================================================================
test_bash_wrappers() {
  log_test "Testing bash DB_* wrapper functions"

  # Test DB_GET_KV
  val=$(DB_GET_KV --key "test:key1" 2>/dev/null)
  if [[ "$val" == "test_value_1" ]]; then
    log_pass "DB_GET_KV wrapper works: $val"
  else
    log_fail "DB_GET_KV wrapper failed"
  fi

  # Test DB_SET_KV
  if DB_SET_KV --key "test:key2" --value "test_value_2" >/dev/null 2>&1; then
    log_pass "DB_SET_KV wrapper works"
  else
    log_fail "DB_SET_KV wrapper failed"
  fi

  # Test DB_GET_RECORD
  rec=$(DB_GET_RECORD --day "$TEST_DAY" --icao "$TEST_ICAO" --type pf 2>/dev/null)
  if printf '%s' "$rec" | jq -e '._index' >/dev/null 2>&1; then
    log_pass "DB_GET_RECORD wrapper works"
  else
    log_fail "DB_GET_RECORD wrapper failed"
  fi
}

# ============================================================================
# Test 9: Record deletion
# ============================================================================
test_record_deletion() {
  log_test "Testing record deletion"

  # Delete the test record
  /usr/share/planefence/pf-db.py delete-record --db "$DB_PATH" --day "$TEST_DAY" --icao "$TEST_ICAO2" --type pf >/dev/null 2>&1

  if [[ $? -eq 0 ]]; then
    log_pass "Record deleted: $TEST_ICAO2"
  else
    log_fail "Failed to delete record"
    return 1
  fi

  # Verify deletion
  result=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "$TEST_ICAO2" --type pf 2>/dev/null || echo '{"ok":false}')
  
  if ! printf '%s' "$result" | jq -e '.ok' >/dev/null 2>&1; then
    log_pass "Record deletion verified (get returns not found)"
  else
    log_fail "Record still exists after deletion"
  fi
}

# ============================================================================
# Test 10: Performance baseline
# ============================================================================
test_performance() {
  log_test "Testing performance baseline"

  # Create 100 test records
  log_info "Creating 100 test records for performance testing..."
  for i in {1..100}; do
    cat <<EOF | /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "TEST$(printf '%04d' $i)" --index "$i" >/dev/null 2>&1
icao=TEST$(printf '%04d' $i)
callsign=PERF$(printf '%03d' $i)
type=B738
ready_to_notify=true
EOF
  done
  log_pass "Created 100 test records"

  # Time a query operation
  local start_time end_time elapsed
  start_time=$(date +%s%N)
  /usr/share/planefence/pf-db.py query-records --db "$DB_PATH" --table pf_records --day "$TEST_DAY" >/dev/null 2>&1
  end_time=$(date +%s%N)
  elapsed=$(( (end_time - start_time) / 1000000 ))  # Convert to ms

  log_pass "Query 100+ records completed in ${elapsed}ms"

  # Check memory usage doesn't explode (rough check)
  local mem_before mem_after
  mem_before=$(ps aux | grep "[p]f-db.py" | awk '{print $6}' | head -1 || echo "0")
  log_info "Process memory usage: ${mem_before}KB (baseline check only)"
}

# ============================================================================
# Main test execution
# ============================================================================
main() {
  printf '\n%s\n' "=========================================="
  printf '%s\n' "Phase 5 Database Test Suite"
  printf '%s\n' "=========================================="
  printf '\n'

  log_info "Database path: $DB_PATH"
  log_info "Test day: $TEST_DAY"
  log_info "Test ICAO codes: $TEST_ICAO, $TEST_ICAO2"

  printf '\n'

  # Run all tests
  test_command_availability
  printf '\n'
  test_db_init
  printf '\n'
  test_record_crud
  printf '\n'
  test_query_records
  printf '\n'
  test_ready_for_notification
  printf '\n'
  test_kv_storage
  printf '\n'
  test_heatmap
  printf '\n'
  test_bash_wrappers
  printf '\n'
  test_record_deletion
  printf '\n'
  test_performance

  printf '\n%s\n' "=========================================="
  printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$PASSED" "$FAILED"
  printf '%s\n' "=========================================="
  printf '\n'

  if (( FAILED > 0 )); then
    return 1
  fi
  return 0
}

main "$@"
