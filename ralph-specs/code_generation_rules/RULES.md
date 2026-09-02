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
- Add tests when they provide meaningful confidence.
- Core logic and non-trivial behavior should be covered; prefer fast, deterministic tests over brittle integration tests.
- Provide seed data that can be loaded into the database on demand.
- For acceptance tests, always seed the database before running tests.
- Run targeted tests only. Do not run the full suite per task. Full-suite runs are for PRD completion, or when changes touch broadly shared code (public API, base classes, DI wiring, config). Same for typecheck: prefer file-scoped or project-scoped over solution-wide.
