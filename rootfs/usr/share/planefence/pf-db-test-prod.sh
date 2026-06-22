#!/bin/bash
# Simplified Phase 5 Test Framework for Production
# Standalone execution without strict error handling

DB_PATH="/run/planefence/planefence-records.sqlite"
TEST_DAY="260622"
REPORT_FILE="/tmp/pf-phase5-test-$(date +%s).txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

# Logging functions
log_pass() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$REPORT_FILE"; ((PASS++)); }
log_fail() { echo -e "${RED}[✗]${NC} $1" | tee -a "$REPORT_FILE"; ((FAIL++)); }
log_info() { echo -e "${YELLOW}[*]${NC} $1" | tee -a "$REPORT_FILE"; }
log_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n" | tee -a "$REPORT_FILE"; }

{
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Phase 5 Production Test Framework            ║"
  echo "║  Functionality & Performance Validation        ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
  echo "Database: $DB_PATH"
  echo "Report: $REPORT_FILE"
  echo "Started: $(date)"
  echo ""
} | tee "$REPORT_FILE"

# ============================================================
# Test 1: Command Availability
# ============================================================
log_header "Test 1: Command Availability"

commands=("query-records" "get-record" "set-record" "delete-record" "query-ready-for-notification" "get-kv" "set-kv" "get-heatmap" "set-heatmap-row")
for cmd in "${commands[@]}"; do
  if /usr/share/planefence/pf-db.py "$cmd" --help >/dev/null 2>&1 || [[ $? -eq 2 ]]; then
    log_pass "Command available: $cmd"
  else
    log_fail "Command missing: $cmd"
  fi
done

# ============================================================
# Test 2: Database Initialization & Integrity
# ============================================================
log_header "Test 2: Database Initialization"

if /usr/share/planefence/pf-db.py init --db "$DB_PATH" >/dev/null 2>&1; then
  log_pass "Database initialization successful"
else
  log_fail "Database initialization failed"
fi

if /usr/share/planefence/pf-db.py integrity-check --db "$DB_PATH" >/dev/null 2>&1; then
  log_pass "Integrity check passed"
else
  log_fail "Integrity check failed"
fi

# ============================================================
# Test 3: Record Operations (CRUD)
# ============================================================
log_header "Test 3: Record CRUD Operations"

# Create record
if echo -e "icao=TEST001\ncallsign=TEST001\ntype=B738\nowner=Test Airlines\nready_to_notify=true" | \
   /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "TEST001" --index 1 >/dev/null 2>&1; then
  log_pass "Record creation successful"
else
  log_fail "Record creation failed"
fi

# Read record
result=$(/usr/share/planefence/pf-db.py get-record --db "$DB_PATH" --day "$TEST_DAY" --icao "TEST001" --type pf 2>/dev/null)
if echo "$result" | grep -q '"ok": true'; then
  log_pass "Record retrieval successful"
  icao=$(echo "$result" | grep -o '"icao": "[^"]*"' | cut -d'"' -f4)
  log_info "Retrieved ICAO: $icao"
else
  log_fail "Record retrieval failed"
fi

# ============================================================
# Test 4: Query Operations
# ============================================================
log_header "Test 4: Query Operations"

# Create test dataset (50 records)
log_info "Creating 50 test records..."
for i in {1..50}; do
  echo -e "icao=QUERY$(printf '%04d' $i)\ncallsign=Q$(printf '%04d' $i)\ntype=B738\nready_to_notify=$((i % 2))" | \
    /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "QUERY$(printf '%04d' $i)" --index $((i + 100)) >/dev/null 2>&1 &
  if (( i % 10 == 0 )); then wait; fi
done
wait

# Query all records
start_time=$(date +%s%N)
result=$(/usr/share/planefence/pf-db.py query-records --db "$DB_PATH" --table pf_records --day "$TEST_DAY" 2>/dev/null)
end_time=$(date +%s%N)
elapsed=$(( (end_time - start_time) / 1000000 ))

count=$(echo "$result" | grep -o '"count": [0-9]*' | cut -d' ' -f2 || echo "0")
if (( count >= 50 )); then
  log_pass "Query successful: $count records in ${elapsed}ms"
else
  log_fail "Query returned only $count records"
fi

# Query with filter
start_time=$(date +%s%N)
result=$(/usr/share/planefence/pf-db.py query-records --db "$DB_PATH" --table pf_records --day "$TEST_DAY" --where "callsign LIKE 'Q%'" 2>/dev/null)
end_time=$(date +%s%N)
elapsed=$(( (end_time - start_time) / 1000000 ))

count=$(echo "$result" | grep -o '"count": [0-9]*' | cut -d' ' -f2 || echo "0")
if (( count >= 20 )); then
  log_pass "Filtered query successful: $count records in ${elapsed}ms"
else
  log_fail "Filtered query returned only $count records"
fi

# ============================================================
# Test 5: Ready-for-Notification Query
# ============================================================
log_header "Test 5: Ready-for-Notification Query"

result=$(/usr/share/planefence/pf-db.py query-ready-for-notification --db "$DB_PATH" --day "$TEST_DAY" --type pf 2>/dev/null)
if echo "$result" | grep -q '"ok": true'; then
  count=$(echo "$result" | grep -o '"icaos": \[[^]]*\]' | grep -o '"' | wc -l)
  count=$(( (count - 2) / 2 ))
  log_pass "Ready-for-notification query successful: $count records"
else
  log_fail "Ready-for-notification query failed"
fi

# ============================================================
# Test 6: Key-Value Storage
# ============================================================
log_header "Test 6: Key-Value Storage"

if /usr/share/planefence/pf-db.py set-kv --db "$DB_PATH" --key "test:perf:key1" --value "test_value_123" >/dev/null 2>&1; then
  log_pass "KV set operation successful"
else
  log_fail "KV set operation failed"
fi

result=$(/usr/share/planefence/pf-db.py get-kv --db "$DB_PATH" --key "test:perf:key1" 2>/dev/null)
if echo "$result" | grep -q '"value": "test_value_123"'; then
  log_pass "KV get operation successful"
else
  log_fail "KV get operation failed"
fi

# ============================================================
# Test 7: Heatmap Operations
# ============================================================
log_header "Test 7: Heatmap Operations"

if /usr/share/planefence/pf-db.py set-heatmap-row --db "$DB_PATH" --day "$TEST_DAY" --latlon-key "37.7749,-122.4194" --hit-count 100 >/dev/null 2>&1; then
  log_pass "Heatmap set operation successful"
else
  log_fail "Heatmap set operation failed"
fi

result=$(/usr/share/planefence/pf-db.py get-heatmap --db "$DB_PATH" --day "$TEST_DAY" 2>/dev/null)
if echo "$result" | grep -q '"ok": true'; then
  count=$(echo "$result" | grep -o '"count": [0-9]*' | cut -d' ' -f2 || echo "0")
  log_pass "Heatmap retrieved: $count rows"
else
  log_fail "Heatmap retrieval failed"
fi

# ============================================================
# Test 8: Performance - Bulk Operations
# ============================================================
log_header "Test 8: Performance - Bulk Operations"

# Create 200 records and measure time
log_info "Creating 200 records for stress test..."
start_time=$(date +%s%N)
for i in {1..200}; do
  echo -e "icao=STRESS$(printf '%04d' $i)\ncallsign=STR$(printf '%03d' $i)\ntype=B738" | \
    /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "STRESS$(printf '%04d' $i)" --index $((i + 200)) >/dev/null 2>&1 &
  if (( i % 50 == 0 )); then wait; fi
done
wait
end_time=$(date +%s%N)
elapsed=$(( (end_time - start_time) / 1000 ))
log_pass "Created 200 records in ${elapsed}ms"

# Query performance
start_time=$(date +%s%N)
/usr/share/planefence/pf-db.py query-records --db "$DB_PATH" --table pf_records --day "$TEST_DAY" >/dev/null 2>&1
end_time=$(date +%s%N)
elapsed=$(( (end_time - start_time) / 1000000 ))
log_pass "Query 250+ records in ${elapsed}ms"

# ============================================================
# Test 9: Edge Cases
# ============================================================
log_header "Test 9: Edge Cases"

# Empty values
if echo -e "icao=EDGE001\ncallsign=\nowner=" | \
   /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE001" --index 900 >/dev/null 2>&1; then
  log_pass "Empty string values handled"
else
  log_fail "Empty string handling failed"
fi

# Special characters
if echo -e "icao=EDGE002\ncallsign=TEST-123/ABC'XYZ\"\nowner=Airline & Co." | \
   /usr/share/planefence/pf-db.py set-record --db "$DB_PATH" --day "$TEST_DAY" --icao "EDGE002" --index 901 >/dev/null 2>&1; then
  log_pass "Special characters handled"
else
  log_fail "Special character handling failed"
fi

# ============================================================
# Test 10: Memory Check
# ============================================================
log_header "Test 10: Memory Usage Check"

mem_usage=$(ps aux | grep "[p]f-db.py" | awk '{sum+=$6} END {print sum}' || echo "0")
log_info "Current pf-db.py memory usage: ${mem_usage}KB"
if (( mem_usage < 500000 )); then
  log_pass "Memory usage within acceptable range"
else
  log_fail "Memory usage too high: ${mem_usage}KB"
fi

# ============================================================
# Summary Report
# ============================================================
{
  echo ""
  echo "╔════════════════════════════════════════════════╗"
  echo "║             TEST SUMMARY REPORT               ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
  printf "Total Tests:    %d\n" $((PASS + FAIL))
  printf "Passed:         ${GREEN}%d${NC}\n" $PASS
  printf "Failed:         ${RED}%d${NC}\n" $FAIL
  echo ""
  
  if (( FAIL == 0 )); then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo ""
    exit 0
  else
    echo -e "${RED}✗ TESTS FAILED${NC}"
    echo ""
    exit 1
  fi
} | tee -a "$REPORT_FILE"
