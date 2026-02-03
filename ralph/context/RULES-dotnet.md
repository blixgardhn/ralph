# Rules (dotnet)

## General
See `RULES.md` for shared guidance (language, development style, safety, observability, runtime, layout, testing). This section lists .NET-specific expectations.

## .NET only (9+ best practices)
- These rules apply only when working on a .NET (9 or higher) solution; ignore this section for non-.NET projects.
- Use SDK-style projects and keep the solution buildable with `dotnet build` and testable with `dotnet test`.
- Use `global.json` to pin the .NET SDK when the repository already uses it.
- Use xUnit for tests unless a different framework is already established in the solution.
- Prefer explicit nullable reference types and avoid suppressing warnings unless there is a clear justification.
- Use async/await for I/O and avoid blocking calls (e.g., `.Result`, `.Wait()`), especially in ASP.NET Core.
- Keep dependency injection registrations consistent and scoped appropriately; avoid service locator patterns.
- Centralize configuration via `IOptions` and environment-specific settings; avoid hardcoded environment flags.
- Favor analyzers and formatting via `dotnet format` (verify-only unless the repo expects auto-fix) or repository standards; do not disable rules broadly.
- Use structured logging with `ILogger<T>` and include meaningful event/context data.
- Prefer minimal, well-typed DTOs for API boundaries; avoid exposing EF/Core entities directly.
- Solution layout conventions: keep production code under `src/`, tests under `tests/`, and align project names with bounded contexts or services.
- Reusable code may be placed in library projects within the solution.

### ASP.NET Core architecture (guidelines, not dogma)
- Use ASP.NET Core MVC conventions to organize functionality (Controllers, Views, Models).
- Prefer clear domain models over generic key/value blobs.
- When building server-rendered web apps, Razor views are the default.
- JavaScript is allowed where it improves UX (e.g., fetch-based interactions).
