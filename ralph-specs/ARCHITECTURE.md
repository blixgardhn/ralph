## Software Architecture Overview

- **Layered architecture**: Separates concerns into presentation, domain, and data layers. Clear boundaries simplify testing, substitution, and scaling. Best for business apps with stable domains.
- **Service-oriented/microservices**: Decomposes capabilities into independently deployable services with well-defined contracts. Enables team autonomy and targeted scaling; requires strong observability and deployment automation.
- **Event-driven**: Uses events as first-class facts to decouple producers from consumers. Fits audit-heavy, workflow, and integration scenarios; demands careful schema/versioning and idempotency.

## Example: Ralph Runner

- **Controller (`ralph.sh`)**: Orchestrates iterations, injects prompt/specs into the target repo, and runs the selected tool image (opencode/amp/claude) with the repo mounted.
- **Specification bundle (`ralph-specs/`)**: Contract files (`prompt.md`, `AGENTS.md`, code generation rules) that define behavior, constraints, and logging. Copied alongside work so the agent follows the same rules in every target repo.
- **Task corpus (`.ralph/tasks.json`)**: PRD-derived stories with `passes` state and dependencies. Drives task selection; only one story per iteration.
- **Progress log (`.ralph/progress.md`)**: Append-only record of changes, commands run, outcomes, patterns, and follow-ups for each iteration.
- **Runner improvements (`.ralph/suggested_improvements.md`)**: Backlog of runner/process ideas kept in the target repo, not the runner root.
- **Verification layer**: Prefer `ralph/verify.sh`; otherwise project-standard checks (e.g., `pnpm typecheck && pnpm test`) run inside containers to keep hosts clean.
- **Branching model**: One feature branch per PRD (`ralph/prd-<id>`). All iterations for that PRD land on that branch; commits happen post-verification, at least once per iteration when changes are made.

## Example: Typical Web Service

- **API layer**: Handles HTTP/GraphQL, authentication, request validation, and response shaping.
- **Domain layer**: Encapsulates business rules, use cases, and policies; persists through repositories/ports.
- **Data layer**: Storage engines (SQL/NoSQL), caches, and message brokers accessed via adapters.
- **Observability**: Centralized logging, metrics, traces, and health endpoints; supports SLOs and alerting.
