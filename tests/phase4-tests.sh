#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://localhost:8243/api/v1/customers}"
CONTAINER_NAME="${CONTAINER_NAME:-wso2am-4.4.0}"
MEDIATOR_POM="${MEDIATOR_POM:-mediator/full-name-normalizer/pom.xml}"

if [[ -z "${ACCESS_TOKEN:-}" ]]; then
  echo "ERROR: ACCESS_TOKEN is not set. Run 'source tests/set-token.sh' first." >&2
  exit 1
fi

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

json_get() {
  local file="$1"
  local expr="$2"
  python3 - "$file" "$expr" << 'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
val = data
for part in sys.argv[2].split("."):
    val = val.get(part) if isinstance(val, dict) else None
print("" if val is None else val)
PY
}

echo "=== TEST 1: Mediator JUnit Unit Tests ==="
if command -v mvn >/dev/null 2>&1; then
  mvn -q -f "${MEDIATOR_POM}" test
  pass "Maven unit tests passed (whitespace, title-case, Arabic->Persian, null/blank)"
else
  echo "SKIP: mvn not found locally; skipping unit tests."
fi

echo ""
echo "=== TEST 2: End-to-End Name Normalization (nationalId=0099887766) ==="
TRACE_ID="trace-p4-norm-$(date +%s)"
HTTP_CODE=$(curl -k -s -o /tmp/p4_t2.json -w "%{http_code}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-Trace-Id: ${TRACE_ID}" \
  "${BASE_URL}/0099887766/overview")

echo "HTTP Status: ${HTTP_CODE}"
cat /tmp/p4_t2.json && echo ""

[[ "${HTTP_CODE}" == "200" ]] || fail "Expected HTTP 200, got ${HTTP_CODE}"

STATUS_CODE=$(json_get /tmp/p4_t2.json "status.code")
RESP_TRACE_ID=$(json_get /tmp/p4_t2.json "traceId")
FULL_NAME=$(json_get /tmp/p4_t2.json "data.fullName")
DEBT_COUNT=$(json_get /tmp/p4_t2.json "data.debtCount")
TOTAL_DEBT=$(json_get /tmp/p4_t2.json "data.totalDebt")

[[ "${STATUS_CODE}" == "SUCCESS" ]] || fail "Expected status.code=SUCCESS, got '${STATUS_CODE}'"
[[ "${RESP_TRACE_ID}" == "${TRACE_ID}" ]] || fail "Expected traceId='${TRACE_ID}', got '${RESP_TRACE_ID}'"
[[ "${FULL_NAME}" == "Ali Rezaei" ]] || fail "Expected normalized fullName='Ali Rezaei', got '${FULL_NAME}'"
[[ "${DEBT_COUNT}" == "1" ]] || fail "Expected debtCount=1, got '${DEBT_COUNT}'"
[[ "${TOTAL_DEBT}" == "1500000" ]] || fail "Expected totalDebt=1500000, got '${TOTAL_DEBT}'"
pass "Messy name '   aLi    rEzAeI  ' normalized to 'Ali Rezaei'"

echo ""
echo "=== TEST 3: Mediator Audit Log Verification ==="
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  LOG_LINE=$(docker logs "${CONTAINER_NAME}" --tail 50 2>&1 | grep "event = FULL_NAME_NORMALIZED" | grep "traceId = ${TRACE_ID}" || true)
  if [[ -n "${LOG_LINE}" ]]; then
    echo "Log: ${LOG_LINE}"
    pass "Mediator execution confirmed in WSO2 Gateway logs for ${TRACE_ID}"
  else
    fail "Expected FULL_NAME_NORMALIZED log for traceId=${TRACE_ID} not found"
  fi
else
  echo "SKIP: Docker container '${CONTAINER_NAME}' not accessible; skipping log assertion."
fi

echo ""
echo "=== TEST 4: Happy-Path Regression Check (nationalId=0012345678) ==="
HTTP_CODE=$(curl -k -s -o /tmp/p4_t4.json -w "%{http_code}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-Trace-Id: trace-p4-reg-001" \
  "${BASE_URL}/0012345678/overview")

echo "HTTP Status: ${HTTP_CODE}"
cat /tmp/p4_t4.json && echo ""

[[ "${HTTP_CODE}" == "200" ]] || fail "Expected HTTP 200 on regression check, got ${HTTP_CODE}"
REG_NAME=$(json_get /tmp/p4_t4.json "data.fullName")
[[ -n "${REG_NAME}" ]] || fail "Expected non-empty fullName on regression check"
pass "Happy-path regression passed (fullName='${REG_NAME}')"

echo ""
echo "ALL PHASE 4 TESTS PASSED"
