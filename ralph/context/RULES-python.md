# Rules (python)

## Language
- Code, comments, commit messages, and documentation must be in English.

## Development style
- Prefer clarity and maintainability over cleverness.
- Make small, incremental changes.
- Avoid premature optimization or over-engineering.
- Use context-appropriate names; avoid placeholders like "MyApp" or "MySolution".

## Safety
- Do not introduce secrets or real credentials.
- Do not break existing functionality unless explicitly required by the PRD.
- Configuration and state changes should be additive where possible.

## Observability
- Applications should provide telemetry and support tracing when suitable.

## Runtime environment
- Target containerized deployments by default.
- Place `Dockerfile` in each project when appropriate; multiple Dockerfiles per repository are allowed.

## Repository layout
- All application source code must live under the `src/` directory at the repository root.
- Do not place application code in the repository root or other directories.
- Configuration, documentation, and automation scripts may live outside `src/`.

## Tests
- Add tests where they add confidence.
- Not every change requires a test, but core logic and non-trivial behavior should be covered.
- Prefer fast, deterministic tests over brittle integration tests.

## Python only (3.11+ best practices)
- These rules apply only when working on a Python (3.11 or higher) project; ignore this section for non-Python projects.
- Use `pytest` for tests unless a different framework is already established in the repository.
- Use type hints for public APIs; avoid `Any` unless necessary.
- Prefer `pathlib` over `os.path` for filesystem paths.
- Use the standard `logging` module for application logs; avoid `print` in production code.
- Follow repository formatting/linting standards (e.g., ruff, black); do not disable rules broadly.
- Avoid blocking calls inside async code paths; use `asyncio`-compatible libraries when needed.
