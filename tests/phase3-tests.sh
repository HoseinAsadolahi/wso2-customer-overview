#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://localhost:8243/api/v1/customers}"
VALID_ID="0012345678"

if [[ -z "${ACCESS_TOKEN:-}" ]]; then
  echo "ERROR: ACCESS_TOKEN is not set. Export a valid JWT first."
  exit 1
fi

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

echo "=== TEST 1: Missing Authorization Header (expected HTTP 401) ==="
HTTP_CODE=$(curl -k -s -o /tmp/p3_t1.json -w "%{http_code}" \
  -H "X-Trace-Id: trace-auth-missing-001" \
  "${BASE_URL}/${VALID_ID}/overview")
echo "HTTP Status: ${HTTP_CODE} | Body: $(cat /tmp/p3_t1.json)"
[[ "${HTTP_CODE}" == "401" ]] && pass "Missing token rejected with 401" || fail "Expected 401, got ${HTTP_CODE}"

echo ""
echo "=== TEST 2: Invalid / Tampered JWT Token (expected HTTP 401) ==="
HTTP_CODE=$(curl -k -s -o /tmp/p3_t2.json -w "%{http_code}" \
  -H "Authorization: Bearer invalid.jwt.signature" \
  -H "X-Trace-Id: trace-auth-invalid-002" \
  "${BASE_URL}/${VALID_ID}/overview")
echo "HTTP Status: ${HTTP_CODE} | Body: $(cat /tmp/p3_t2.json)"
[[ "${HTTP_CODE}" == "401" ]] && pass "Invalid JWT rejected with 401" || fail "Expected 401, got ${HTTP_CODE}"

echo ""
echo "=== TEST 3: Valid JWT Format & Authenticated Call (expected HTTP 200) ==="
DOT_COUNT=$(awk -F'.' '{print NF-1}' <<< "${ACCESS_TOKEN}")
if [[ "${DOT_COUNT}" -ne 2 ]]; then
  fail "ACCESS_TOKEN does not look like a 3-part JWT (dots found: ${DOT_COUNT})"
fi
echo "JWT format verified (3 dot-separated segments)."

HTTP_CODE=$(curl -k -s -o /tmp/p3_t3.json -w "%{http_code}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-Trace-Id: trace-auth-valid-003" \
  "${BASE_URL}/${VALID_ID}/overview")
echo "HTTP Status: ${HTTP_CODE} | Body: $(cat /tmp/p3_t3.json)"
[[ "${HTTP_CODE}" == "200" ]] && pass "Valid JWT accepted with 200" || fail "Expected 200, got ${HTTP_CODE}"

echo ""
echo "=== TEST 4: Rate Limiting 10 req/min (sending 14 more requests, expecting HTTP 429) ==="
OK_COUNT=1 # Includes Test 3
THROTTLE_COUNT=0
LAST_429_BODY=""

for i in $(seq 2 15); do
  HTTP_CODE=$(curl -k -s -o /tmp/p3_t4.json -w "%{http_code}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "X-Trace-Id: trace-throttle-$(printf '%03d' "${i}")" \
    "${BASE_URL}/${VALID_ID}/overview")
  echo "  Request #${i}: HTTP ${HTTP_CODE}"
  if [[ "${HTTP_CODE}" == "200" ]]; then
    OK_COUNT=$((OK_COUNT + 1))
  elif [[ "${HTTP_CODE}" == "429" ]]; then
    THROTTLE_COUNT=$((THROTTLE_COUNT + 1))
    LAST_429_BODY=$(cat /tmp/p3_t4.json)
  else
    fail "Unexpected HTTP ${HTTP_CODE} on request #${i}: $(cat /tmp/p3_t4.json)"
  fi
  sleep 0.3
done

echo "Summary: ${OK_COUNT} succeeded (200), ${THROTTLE_COUNT} throttled (429)"
if [[ "${THROTTLE_COUNT}" -ge 1 ]]; then
  echo "Sample 429 Body: ${LAST_429_BODY}"
  pass "Rate limit enforced with HTTP 429"
else
  fail "No HTTP 429 received after 15 requests within 1 minute"
fi

echo ""
echo "ALL PHASE 3 TESTS PASSED"
