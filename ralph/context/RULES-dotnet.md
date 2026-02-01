# Rules (dotnet)

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
- Target containerized deployments by default, keep compatibility with IIS when feasible.
- Place `Dockerfile` in each project when appropriate; multiple Dockerfiles per repository are allowed.

## Repository layout
- All application source code must live under the `src/` directory at the repository root.
- Do not place application code in the repository root or other directories.
- Configuration, documentation, and automation scripts may live outside `src/`.

## Tests
- Add tests where they add confidence.
- Not every change requires a test, but core logic and non-trivial behavior should be covered.
- Prefer fast, deterministic tests over brittle integration tests.

## .NET only (9+ best practices)
- These rules apply only when working on a .NET (9 or higher) solution; ignore this section for non-.NET projects.
- Use SDK-style projects and keep the solution buildable with `dotnet build` and testable with `dotnet test`.
- Use xUnit for tests unless a different framework is already established in the solution.
- Prefer explicit nullable reference types and avoid suppressing warnings unless there is a clear justification.
- Use async/await for I/O and avoid blocking calls (e.g., `.Result`, `.Wait()`), especially in ASP.NET Core.
- Keep dependency injection registrations consistent and scoped appropriately; avoid service locator patterns.
- Centralize configuration via `IOptions` and environment-specific settings; avoid hardcoded environment flags.
- Favor analyzers and formatting via `dotnet format` or repository standards; do not disable rules broadly.
- Use structured logging with `ILogger<T>` and include meaningful event/context data.
- Prefer minimal, well-typed DTOs for API boundaries; avoid exposing EF/Core entities directly.
- Solution layout conventions: keep production code under `src/`, tests under `tests/`, and align project names with bounded contexts or services.
- Reusable code may be placed in library projects within the solution.

### ASP.NET Core architecture (guidelines, not dogma)
- Use ASP.NET Core MVC conventions to organize functionality (Controllers, Views, Models).
- Prefer clear domain models over generic key/value blobs.
- Server-rendered HTML (Razor views) is the default.
- JavaScript is allowed where it improves UX (e.g., fetch-based interactions).
