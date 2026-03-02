## Software Architecture Overview

- **Layered architecture**: Separates presentation, domain, and data concerns to enable substitution, scaling, and focused testing. Suits business apps with stable domains.
- **Service-oriented/microservices**: Splits capabilities into independently deployable services with clear contracts. Enables team autonomy and targeted scaling; requires strong observability and deployment automation.
- **Event-driven**: Treats events as facts to decouple producers from consumers. Fits audit-heavy, workflow, and integration scenarios; demands schema/version discipline and idempotency.

## Reference Architecture: Web Application

- **Client/UI**: SPA/SSR front-end consuming typed APIs; handles routing, state, accessibility, and error presentation.
- **API gateway**: Terminates HTTP, enforces authn/z, rate limits, and request validation; forwards to services.
- **Application services**: Domain use-cases coordinating validation, policies, and persistence through ports/adapters.
- **Data layer**: Primary store (SQL/NoSQL) plus cache; migrations/versioning owned alongside code.
- **Async jobs/events**: Message broker or queue for long-running or fan-out work; workers are idempotent and observable.
- **Observability**: Structured logs, metrics, traces, and health endpoints; dashboards and alerts tied to SLOs.

## Reference Architecture: Data/ML Pipeline

- **Ingestion**: Batch/stream connectors pull from source systems with schema tracking and back-pressure handling.
- **Storage**: Raw and curated zones (object store or warehouse) with versioned schemas and retention policies.
- **Processing**: Transformations via notebooks, scheduled jobs, or DAGs; unit tests on transforms and contracts on outputs.
- **Serving**: Feature store or model server exposes stable interfaces; includes A/B rollout and drift monitoring.
- **Observability**: Data quality checks, lineage, and cost/latency metrics feeding alerts and dashboards.
