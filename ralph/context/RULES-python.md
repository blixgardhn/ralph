# Rules (python)

## General
See `RULES.md` for shared guidance (language, development style, safety, observability, runtime, layout, testing). This section lists Python-specific expectations.

## Python only (3.11+ best practices)
- These rules apply only when working on a Python (3.11 or higher) project; ignore this section for non-Python projects.
- Use `pytest` for tests unless a different framework is already established in the repository.
- Use type hints for public APIs; avoid `Any` unless necessary.
- Prefer `pathlib` over `os.path` for filesystem paths.
- Use the standard `logging` module for application logs; avoid `print` in production code.
- Use `pyproject.toml` as the source of truth for tooling configuration when present.
- Follow repository formatting/linting standards (e.g., ruff, black, mypy); do not disable rules broadly.
- Avoid blocking calls inside async code paths; use `asyncio`-compatible libraries when needed.

## Preferred application frameworks (when starting a new app)
- Web apps and REST backends: prefer Django unless clearly overkill, then use FastAPI; always defer to the repository's existing framework.
  - Clearly overkill examples: a small service with only a few endpoints, no admin site, no relational ORM needs, or a lightweight CRUD API without complex auth or model relationships.
- App frontends (Python-based): any Python framework is acceptable; prefer the repository's existing choice.
- Web frontend (if needed): prefer Vue.js.
- CLIs: prefer Typer for modern CLI apps; use Click only when already established.
- Background jobs: prefer APScheduler for lightweight scheduling; use Celery only when distributed execution is required.
