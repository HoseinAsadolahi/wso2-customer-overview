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