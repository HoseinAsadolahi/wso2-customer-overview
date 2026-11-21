# WSO2 APIM 4.4.0 — Customer Overview Integration

API integration project on **WSO2 API Manager 4.4.0** (Docker) aggregating customer and debt services with JWT auth, rate limiting, and a custom Java Class Mediator.

## Prerequisites
- Docker & Docker Compose
- `curl`
- Java 17+ & Maven 3.8+ (Phase 4)

## Phase 1: WSO2 APIM 4.4.0 Setup (Docker)

### 1. Run
```bash
cp docker/.env.example docker/.env
cd docker
docker compose up -d
```

Wait ~60–90s for startup (`WSO2 Carbon started`), then verify health:

```bash
docker compose ps   # Expect: wso2am-4.4.0 (healthy)gs
```

### 2. Portals & Gateway

Default credentials: `admin` / `admin` (accept self-signed cert).

| Service | URL |
| --- | --- |
| Publisher | `https://localhost:9443/publisher` |
| Developer Portal | `https://localhost:9443/devportal` |
| Gateway (HTTPS) | `https://localhost:8243` |

### 3. Smoke Test

1. In **Publisher**, click **Deploy Sample API** (`PizzaShackAPI 1.0.0`).
2. In **Developer Portal**, open **PizzaShackAPI** → **Try Out** → **GET TEST KEY**.
3. Call the Gateway (replace `<ACCESS_TOKEN>`):

```bash
curl -k -i "https://localhost:8243/pizzashack/1.0.0/menu" \
  -H "accept: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

**Expected Response (`200 OK`):**

```json
[
  {
    "name": "Chicken Parmesan",
    "description": "Grilled chicken, fresh tomatoes, feta and mozzarella cheese",
    "price": "10.00",
    "icon": "/images/1.png"
  }
]
```

### 4. Stop

```bash
cd docker && docker compose down
```
## Phase 2: API Orchestration, Error Handling & Observability

### Architecture Overview

`CustomerOverviewAPI` (`GET /api/v1/customers/{nationalId}/overview`) orchestrates two downstream services (`mock-customer` and `mock-debt`) entirely within self-contained WSO2 APIM 4.4.0 API artifacts—requiring **no global server modifications** (`fault.xml` or `deployment.toml`).

- **Sequence Backend (`api/mediation/customer-overview-backend.xml`):**
  - Bound to the API via **Endpoints → Sequence Backend** with `onError="CustomerOverviewAPI:vv1--Fault"`.
  - Initializes and propagates `traceId` from the incoming `X-Trace-Id` header (or falls back to the Synapse `MessageID` UUID) in both logs and response headers/payloads.
  - Validates `nationalId` (must be exactly 10 numeric digits; otherwise returns `400 BAD_REQUEST`).
  - Invokes `mock-customer` and `mock-debt` sequentially using `<call blocking="true">` with a `3000ms` timeout, `non.error.http.status.codes` (`400,404,500,502,503`), and `<errorCodes>-1</errorCodes>` to disable endpoint suspension (`303001`).
  - Validates upstream HTTP statuses and JSON business/schema contracts, returning `404 NOT_FOUND` or `502 BAD_GATEWAY` on violations.
  - Aggregates both responses into the unified `200 SUCCESS` JSON contract (including computed `debtCount`).
- **API-Level Fault Policy (`api/mediation/customer-overview-fault.j2`):**
  - Attached at **API Level Policies → Fault Flow** as `CustomerOverviewFault`.
  - Uses body-safe property filters (`source`/`regex`, zero `xpath=`) so malformed JSON payloads do not trigger secondary `XMLStreamException` crashes inside the fault handler.
  - Maps blocking/non-blocking timeout codes (`101504|401002`) to `504 GATEWAY_TIMEOUT` and all other transport/parse failures to `502 BAD_GATEWAY`.

---

### Mediation Artifacts

| File | Role | WSO2 Publisher Location |
| :--- | :--- | :--- |
| `api/mediation/customer-overview-backend.xml` | Main orchestration, validation, and aggregation sequence | **Endpoints → Sequence Backend** (Production & Sandbox) |
| `api/mediation/customer-overview-fault.j2` | Body-safe fault handler (`504` / `502` contract) | **Policies → API Level Policies → Fault Flow** |
| `tests/phase2-tests.sh` | Automated end-to-end verification suite (7 scenarios) | Local CLI |

---

### Setup & Deployment (Clean Environment)

1. **Start the Docker stack:**
   ```bash
   docker compose -f docker/docker-compose.yml up -d
   ```
   Wait until `docker logs wso2am-4.4.0` shows `WSO2 Carbon started`.

2. **Configure `CustomerOverviewAPI` in Publisher (`https://localhost:9443/publisher`):**
   - **Import OpenAPI:** Create `CustomerOverviewAPI` with Context `/api` and Version `v1`.
   - **Sequence Backend:** Under **API Configurations → Endpoints → Sequence Backend**, upload `api/mediation/customer-overview-backend.xml` as the **Production Sequence** (and optionally Sandbox) and save.
   - **Fault Policy:** Under **API Configurations → Policies → API Specific Policies**, create `CustomerOverviewFault` (Applicable Flow: **Fault**, Gateway: **Regular Gateway**) using `api/mediation/customer-overview-fault.j2`. Attach it under **API Level Policies → Fault Flow** and save.
   - **Subscriptions & Lifecycle:** Enable the `Unlimited` business plan under **Portal Configurations → Subscriptions**, deploy a new revision (**Deploy → Deploy New Revision**), and publish the API (**Publish → Lifecycle → Publish**).

3. **Subscribe & Generate an Access Token in Developer Portal (`https://localhost:9443/devportal`):**
   - Subscribe `DefaultApplication` (`Unlimited` tier) to `CustomerOverviewAPI`.
   - Go to **Applications → DefaultApplication → Production Keys → OAuth2 Tokens** and click **GENERATE KEYS**, then **GENERATE ACCESS TOKEN** (or use **Try Out → GET TEST KEY**).

---

### Verification

Export the generated Bearer token and run the Phase 2 test suite:

```bash
export ACCESS_TOKEN="<PASTE_TOKEN_HERE>"
./tests/phase2-tests.sh
```

#### Covered Test Scenarios

| # | Scenario | `nationalId` | Expected HTTP | Status Code |
| :--- | :--- | :--- | :--- | :--- |
| 1 | Happy Path (unified response + `debtCount=2`) | `0012345678` | `200` | `SUCCESS` |
| 2 | Invalid `nationalId` format | `12345` | `400` | `BAD_REQUEST` |
| 3 | Customer not found in Backend A | `0000000404` | `404` | `NOT_FOUND` |
| 4 | Backend B HTTP 500 error | `0000000500` | `502` | `BAD_GATEWAY` |
| 5 | Backend B business/schema error | `0000000501` | `502` | `BAD_GATEWAY` |
| 6 | Backend B malformed/invalid JSON (`XMLStreamException`) | `0000000502` | `502` | `BAD_GATEWAY` |
| 7 | Backend B timeout (`> 3000ms`, `ERROR_CODE=401002`) | `0000000504` | `504` | `GATEWAY_TIMEOUT` |

To inspect structured `traceId` and fault logs:

```bash
docker logs wso2am-4.4.0 --tail 40 | grep -E "CUSTOMER_OVERVIEW|DEBT_BACKEND"
```