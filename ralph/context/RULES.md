# Rules (General)

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
- Place a `Dockerfile` in each project when appropriate; multiple Dockerfiles are allowed.

## Repository layout
- Application source code lives under `src/` at the repository root.
- Do not place application code in the repository root or unrelated directories.
- Configuration, documentation, and automation scripts may live outside `src/`.

## Tests
- Add tests when they provide meaningful confidence.
- Core logic and non-trivial behavior should be covered; prefer fast, deterministic tests over brittle integration tests.
