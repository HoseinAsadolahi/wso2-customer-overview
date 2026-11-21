# WSO2 API Manager 4.4.0 — Customer Overview Integration

API integration project built on **WSO2 API Manager 4.4.0** (Docker) that aggregates customer and debt data from two backend services, secured with OAuth2/JWT, API-level rate limiting, and a custom Java Class Mediator.

## Prerequisites

- Docker & Docker Compose
- `curl` (for testing Gateway endpoints)
- Java 17+ & Maven 3.8+ (required in Phase 4 for building the Class Mediator JAR)

## Repository Structure

```text
.
├── docker/
│   ├── docker-compose.yml    # WSO2 APIM 4.4.0 (and mock backends in Phase 2)
│   └── .env.example          # Configurable ports and image settings
├── mocks/                    # Mock backend definitions (Phase 2)
├── api/                      # OpenAPI spec and Synapse mediation policies (Phase 2)
├── mediator/                 # Java Class Mediator Maven project (Phase 4)
├── tests/                    # Automated cURL / Postman test suites
└── README.md
