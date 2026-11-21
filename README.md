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
## Phase 3: Security (OAuth2 / JWT) & Rate Limiting

### Security & Throttling Architecture

- **OAuth2 / JWT Enforcement:**
  - Application-level security is set to **OAuth2 (Mandatory)** over **HTTPS**, with endpoint security enabled on `GET /customers/{nationalId}/overview`.
  - WSO2 APIM 4.4.0's Resident Key Manager issues self-contained **RS256-signed JWT** access tokens by default via the `client_credentials` (or `password`) grant at `https://localhost:9443/oauth2/token`.
  - The Gateway validates token signatures, expiration (`exp`), and active subscriptions locally before routing traffic to `customer-overview-backend`.
- **Rate Limiting (`10PerMin`):**
  - Enforced via a custom Subscription Rate Limiting Policy (`10PerMin`: **10 requests per 1 minute**, **Stop On Quota Reach** enabled).
  - Bound as the exclusive business plan on `CustomerOverviewAPI` so subscribed applications cannot exceed the quota (`HTTP 429`, WSO2 error code `900804`).

---

### Artifacts Added

| File | Role |
| :--- | :--- |
| `.env.example` | Template for `CONSUMER_KEY` and `CONSUMER_SECRET` (real `.env` is gitignored) |
| `tests/set-token.sh` | Sourced helper script that fetches a JWT from `https://localhost:9443/oauth2/token` and exports `ACCESS_TOKEN` |
| `tests/phase3-tests.sh` | Automated verification suite for `401` auth checks, JWT structure, and `429` throttling |

---

### Setup & Configuration (Clean Environment)

1. **Create the `10PerMin` Subscription Policy in Admin Portal (`https://localhost:9443/admin`):**
   - Go to **Rate Limiting Policies → Subscription Policies → Add Policy**.
   - Set **Name:** `10PerMin`, **Quota Type:** `Request Count`, **Request Count:** `10`, **Unit Time:** `1` **Minutes**, **Stop On Quota Reach:** Checked, **Billing Plan:** `Free`, and click **Save**.
2. **Bind Policy & Verify Security in Publisher (`https://localhost:9443/publisher`):**
   - Under **API Configurations → Runtime**, ensure **OAuth2 (Mandatory)** and **HTTPS** are enabled.
   - Under **Portal Configurations → Subscriptions**, select **10PerMin** only (uncheck `Unlimited`), save, and **Deploy New Revision**.
3. **Update Application Subscription & Credentials in Developer Portal (`https://localhost:9443/devportal`):**
   - Under **Applications → DefaultApplication → Subscriptions**, update `CustomerOverviewAPI (v1)` to the **10PerMin** business plan.
   - Copy the **Production** `Consumer Key` and `Consumer Secret` into a local `.env` file (based on `.env.example`):
     ```bash
     cp .env.example .env
     # Fill in CONSUMER_KEY and CONSUMER_SECRET
     ```

---

### Verification

Fetch a fresh JWT programmatically and run the Phase 3 suite:

```bash
source tests/set-token.sh
./tests/phase3-tests.sh
```

#### Covered Test Scenarios

| # | Scenario | Expected HTTP | Notes |
| :--- | :--- | :--- | :--- |
| 1 | Missing `Authorization` header | `401` | Rejected by Gateway authentication handler |
| 2 | Invalid / tampered JWT token | `401` | Signature/format rejected (`invalid.jwt.signature`) |
| 3 | Valid JWT (`client_credentials`) | `200` | Verifies 3-segment JWT format and successful backend orchestration |
| 4 | Burst exceeding 10 req/min (15 requests, 0.3s interval) | `429` | Enforces `10PerMin` quota via embedded Traffic Manager |

*(Note: After triggering `429`, wait ~60 seconds for the 1-minute throttling window to reset before re-running the test suite.)*

## Phase 4: Custom Java Class Mediator (`FullNameNormalizerMediator`)

### Architecture & Normalization Rules

A standalone Java Class Mediator (`com.customeroverview.mediator.FullNameNormalizerMediator`) extending `org.apache.synapse.mediators.AbstractMediator` normalizes customer names during sequence execution before the unified JSON response is built:

- **Whitespace Normalization:** Trims leading/trailing whitespace and collapses repeated spaces, tabs, newlines, and non-breaking spaces (`\u00A0`) into a single space.
- **Persian/Arabic Character Unification:** Converts Arabic `ي` (`\u064A`) and `ك` (`\u0643`) to standard Persian `ی` (`\u06CC`) and `ک` (`\u06A9`).
- **Casing Normalization:** Applies token-level title-casing for Latin names (e.g., `"   aLi    rEzAeI  "` → `"Ali Rezaei"`) while preserving non-Latin scripts.
- **Configurable Synapse Properties:** Supports `<property name="inputProperty"/>` (default: `rawFullName`) and `<property name="outputProperty"/>` (default: `normalizedFullName`), and emits an audit log entry containing `traceId`.
- **Portable Maven Build:** Targets Java 11 bytecode with `org.apache.synapse:synapse-core:3.0.1` (`provided` scope) and excludes legacy HTTP-only transitive WSO2 artifacts so the project builds cleanly from Maven Central on Maven 3.8.1+.

---

### Artifacts Added / Updated

| File | Role |
| :--- | :--- |
| `mediator/full-name-normalizer/pom.xml` | Maven build configuration (Java 11, `synapse-core` provided, JUnit 5) |
| `mediator/full-name-normalizer/src/main/java/com/customeroverview/mediator/FullNameNormalizerMediator.java` | Custom Synapse Class Mediator implementation |
| `mediator/full-name-normalizer/src/test/java/com/customeroverview/mediator/FullNameNormalizerMediatorTest.java` | JUnit 5 unit tests for normalization edge cases |
| `api/mediation/customer-overview-backend.xml` | Wired `<class name="com.customeroverview.mediator.FullNameNormalizerMediator">` in place of the pass-through property |
| `docker/docker-compose.yml` | Bind-mounts the built JAR into WSO2's `repository/components/lib/` for automatic OSGi conversion on startup |
| `mocks/customer-service/mappings/customer-messy-name.json` & `mocks/debt-service/mappings/debt-messy-name.json` | WireMock fixtures (`nationalId=0099887766`) returning unnormalized `fullName` data |
| `tests/phase4-tests.sh` | Automated unit + end-to-end verification script |

---

### Build & Deployment (Clean Environment)

1. **Build the mediator JAR (required before starting Docker on a fresh clone):**
   ```bash
   mvn -f mediator/full-name-normalizer/pom.xml clean package
   ```
   *(This generates `mediator/full-name-normalizer/target/full-name-normalizer-mediator-1.0.0.jar`, which `docker/docker-compose.yml` mounts into `/home/wso2carbon/wso2am-4.4.0/repository/components/lib/`.)*

2. **Start or restart WSO2 APIM:**
   - On a clean environment, `docker compose -f docker/docker-compose.yml up -d` loads the JAR automatically and converts it into an OSGi bundle in `repository/components/dropins/`.
   - On an existing running container (to preserve H2 state), copy the JAR into `repository/components/lib/` and run `docker restart wso2am-4.4.0`.

3. **Deploy the updated sequence in Publisher (`https://localhost:9443/publisher`):**
   - Upload `api/mediation/customer-overview-backend.xml` under **CustomerOverviewAPI → Endpoints → Sequence Backend**, click **Save**, and **Deploy New Revision**.

---

### Verification

```bash
source tests/set-token.sh
./tests/phase4-tests.sh
```

#### Covered Test Scenarios

| # | Check | Verification Criteria |
| :--- | :--- | :--- |
| 1 | JUnit 5 Unit Tests | Whitespace collapsing, Latin title-casing, Arabic-to-Persian character normalization, and null/blank handling |
| 2 | E2E Name Normalization (`0099887766`) | `HTTP 200`, `status.code=SUCCESS`, `"   aLi    rEzAeI  "` transformed to `"Ali Rezaei"`, `debtCount=1`, `traceId` echoed |
| 3 | Gateway Audit Log | Confirms `FullNameNormalizerMediator executed` logged with matching `traceId` |
| 4 | Regression (`0012345678`) | Existing Phase 2 happy-path flow continues returning `HTTP 200` with normalized `fullName` |