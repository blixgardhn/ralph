# Rules (General)

## Scope
- These rules apply by default; language-specific rules override where applicable.

## Language
- Code, comments, commit messages, and documentation must be in English.

## Development style
- Prefer clarity and maintainability over cleverness.
- Make small, incremental changes.
- Avoid premature optimization or over-engineering.
- Use context-appropriate names; avoid placeholders.

## Safety
- Do not introduce secrets or real credentials.
- Do not break existing functionality unless explicitly required by the PRD.
- Make configuration and state changes additive when possible.

## Observability
- Provide telemetry and tracing when suitable for the domain.

## Runtime environment
- Run development, dependency installation, linting, testing, builds, and diagnostics inside containers; keep the host environment untouched.
- Provide a containerized entrypoint (Dockerfile and/or Compose) appropriate to the repository.
- When running the software (any service/app), run it in a container unless explicitly stated otherwise.
- When running code generation that requires tooling, use a container based on a base image appropriate to the task.

## Repository layout
- Follow best practices for the relevant language and type of project when choosing code location and layout.
- Configuration, documentation, and automation scripts may live outside application code directories.

## Docs
- Update README only when user-facing behavior changes.

## Tests
- Add tests only when they add meaningful confidence for non-trivial behavior. There is no test quota — do not add tests for CRUD, DTOs, wiring, or code obvious by inspection. A task is not incomplete for lacking new tests.
- When tests are warranted, cover core/non-trivial logic; prefer fast, deterministic tests over brittle integration tests.
- Provide seed data that can be loaded into the database on demand.
- For acceptance tests, always seed the database before running tests.
- Verification (typecheck/tests) is opt-in per iteration, not a per-task gate — see the Verification Policy in `prompt.md`. Default to skipping; run scoped checks only when a trigger fires; batch to consolidation checkpoints. Never run the full suite or solution-wide typecheck per task.
