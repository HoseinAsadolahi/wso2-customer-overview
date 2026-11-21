#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://localhost:8243/api/v1}"
TOKEN="${ACCESS_TOKEN:?Set ACCESS_TOKEN env var first}"

run_test() {
  local name="$1"
  local national_id="$2"
  local expected_status="$3"
  local trace_id="$4"

  echo "=========================================="
  echo "TEST: $name (nationalId=$national_id | expected HTTP $expected_status)"

  local response
  response=$(curl -k -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Trace-Id: $trace_id" \
    "$BASE_URL/customers/$national_id/overview")

  local http_code
  http_code=$(echo "$response" | tail -n1)
  local body
  body=$(echo "$response" | sed '$d')

  echo "HTTP Status: $http_code"
  echo "Body: $body"

  if [ "$http_code" -ne "$expected_status" ]; then
    echo "FAIL: expected $expected_status, got $http_code"
    return 1
  fi
  echo "PASS"
}

run_test "1. Happy Path (Unified Response + debtCount=2)" "0012345678" 200 "trace-happy-001"
run_test "2. Invalid National ID (not 10 digits)"         "12345"      400 "trace-badreq-002"
run_test "3. Customer Not Found in Backend A"             "0000000404" 404 "trace-notfound-003"
run_test "4. Backend B HTTP 500 Error"                    "0000000500" 502 "trace-http500-004"
run_test "5. Backend B Business Error (code != OK)"       "0000000501" 502 "trace-bizerr-005"
run_test "6. Backend B Malformed/Invalid JSON"            "0000000502" 502 "trace-badjson-006"
run_test "7. Backend B Timeout (10s delay vs 3s timeout)" "0000000504" 504 "trace-timeout-007"

echo "=========================================="
echo "ALL PHASE 2 TESTS PASSED"
