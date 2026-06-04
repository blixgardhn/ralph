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

### Restore/build prerequisites

A private NuGet feed is used when `NUGET_PRIVATE_FEED_URL` is set in the environment. All `dotnet restore` and `dotnet build` commands must mount `nuget.config` and pass the feed credentials.

**Concrete docker run pattern:**

```bash
docker run --rm \
  -v "$PWD":/work \
  -v "$RALPH_ROOT/ralph-specs/resources/nuget.config":/work/nuget.config:ro \
  -e NUGET_PRIVATE_FEED_URL="$NUGET_PRIVATE_FEED_URL" \
  -e NUGET_API_KEY="$NUGET_API_KEY" \
  -w /work \
  mcr.microsoft.com/dotnet/sdk:9.0 \
  dotnet build
```

**Concrete docker compose pattern** — add to the service in `docker-compose.yml`:

```yaml
volumes:
  - ${RALPH_ROOT}/ralph-specs/resources/nuget.config:/app/nuget.config:ro
environment:
  NUGET_PRIVATE_FEED_URL: ${NUGET_PRIVATE_FEED_URL:-}
  NUGET_API_KEY: ${NUGET_API_KEY:-}
```

Rules:
- Always mount `nuget.config` from `$RALPH_ROOT/ralph-specs/resources/nuget.config` — do not copy or commit it into the target repo.
- Always forward `NUGET_PRIVATE_FEED_URL` and `NUGET_API_KEY` — they come from the host environment (set in the target repo's `.env`).
- If `NUGET_PRIVATE_FEED_URL` is empty the private feed entry in `nuget.config` is a no-op; builds still work against nuget.org.
- Do not commit credentials or hardcode feed URLs.
### ASP.NET Core architecture (guidelines, not dogma)
- Use ASP.NET Core MVC conventions to organize functionality (Controllers, Views, Models).
- Prefer clear domain models over generic key/value blobs.
- When building server-rendered web apps, Razor views are the default.
- JavaScript is allowed where it improves UX (e.g., fetch-based interactions).
