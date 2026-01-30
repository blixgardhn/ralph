# Rules

## Language
- Code, comments, commit messages, and documentation must be in English.

## Development style
- Prefer clarity and maintainability over cleverness.
- Small, incremental changes are preferred.
- Avoid premature optimization or over-engineering.
- Ensure naming for all items and entities are according to best practice for current context. Avoid for example "MyApp" or "MySolution"

## Architecture (guidelines, not dogma)
- Use ASP.NET Core MVC conventions to organize functionality (Controllers, Views, Models).
- Prefer clear domain models over generic key/value blobs.
- Server-rendered HTML (Razor views) is the default.
- JavaScript is allowed where it improves UX (e.g., fetch-based interactions).

## Safety
- Do not introduce secrets or real credentials.
- Do not break existing functionality unless explicitly required by the PRD.
- Configuration and state changes should be additive where possible.

## Tests
- Add tests where they add confidence.
- Not every change requires a test, but core logic and non-trivial behavior should be covered.
- Prefer fast, deterministic tests over brittle integration tests.

## Repository layout
- All application source code must live under the `src/` directory at the repository root.
- Do not place application code in the repository root or other directories.
- Configuration, documentation, and automation scripts may live outside `src/`.
