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
  -e PROGET_DOTNET_TOKEN="$PROGET_DOTNET_TOKEN" \
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
  PROGET_DOTNET_TOKEN: ${PROGET_DOTNET_TOKEN:-}
```

Rules:
- Always mount `nuget.config` from `$RALPH_ROOT/ralph-specs/resources/nuget.config` — do not copy or commit it into the target repo.
- Always forward `NUGET_PRIVATE_FEED_URL` and `PROGET_DOTNET_TOKEN` — they come from the host environment (set in the target repo's `.env`).
- If `NUGET_PRIVATE_FEED_URL` is empty the private feed entry in `nuget.config` is a no-op; builds still work against nuget.org.
- Do not commit credentials or hardcode feed URLs.

### `docker build` with private NuGet feed (BuildKit secret pattern)

`docker run` / `docker compose` runtime patterns above do **not** work for `docker build` (image build time). Env vars from the host are not visible during `RUN`, and bind mounts don't exist. Use BuildKit secrets so the ProGet token reaches `dotnet restore` **without being baked into image layers**.

**Requirements:**
- BuildKit must be enabled (`DOCKER_BUILDKIT=1`, or Docker 23+ where it's default; Podman uses `--secret` similarly).
- `nuget.config` must be present in the build context (copy it in from `$RALPH_ROOT/ralph-specs/resources/nuget.config` just before `docker build`, or use `--build-context`). Do not commit it.
- The cert-install block from `CERT_RULES.md` must run **before** `dotnet restore`, otherwise TLS to ProGet fails and looks like an auth error.

**Dockerfile pattern (multi-stage, secret-safe):**

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BASE_SDK=mcr.microsoft.com/dotnet/sdk:9.0
FROM ${BASE_SDK} AS build

# ... cert-install block from CERT_RULES.md goes here (before any network RUN) ...

WORKDIR /src
COPY nuget.config ./nuget.config
COPY . .

# Secret is mounted as a file at /run/secrets/proget_token for the duration of this RUN only.
# NUGET_PRIVATE_FEED_URL is a non-secret build arg (URLs aren't sensitive here).
ARG NUGET_PRIVATE_FEED_URL=""
RUN --mount=type=secret,id=proget_token,required=true \
    PROGET_DOTNET_TOKEN="$(cat /run/secrets/proget_token)" \
    NUGET_PRIVATE_FEED_URL="${NUGET_PRIVATE_FEED_URL}" \
    dotnet restore --configfile ./nuget.config

RUN dotnet publish -c Release -o /out --no-restore
```

Notes:
- The token is available only inside that single `RUN` — it never enters an image layer, `docker history`, or the final image.
- `nuget.config` uses `%PROGET_DOTNET_TOKEN%` / `%NUGET_PRIVATE_FEED_URL%`, which NuGet expands from the env vars set inline on the `RUN`.
- `required=true` fails the build fast if the secret wasn't passed (better than a silent 401).

**`docker build` invocation:**

```bash
DOCKER_BUILDKIT=1 docker build \
  --build-arg NUGET_PRIVATE_FEED_URL="$NUGET_PRIVATE_FEED_URL" \
  --build-arg PROXY_CERT_URL="$PROXY_CERT_URL" \
  --build-arg ISSUING_CA_CERT_URL="$ISSUING_CA_CERT_URL" \
  --build-arg ROOT_CA_CERT_URL="$ROOT_CA_CERT_URL" \
  --secret id=proget_token,env=PROGET_DOTNET_TOKEN \
  -t myapp:local .
```

**`docker compose` build (compose v2.5+):**

```yaml
services:
  app:
    build:
      context: .
      args:
        NUGET_PRIVATE_FEED_URL: ${NUGET_PRIVATE_FEED_URL:-}
        PROXY_CERT_URL: ${PROXY_CERT_URL:-}
        ISSUING_CA_CERT_URL: ${ISSUING_CA_CERT_URL:-}
        ROOT_CA_CERT_URL: ${ROOT_CA_CERT_URL:-}
      secrets:
        - proget_token
secrets:
  proget_token:
    environment: PROGET_DOTNET_TOKEN
```

Build with: `DOCKER_BUILDKIT=1 docker compose build`.

**Common failure modes and diagnosis:**
- `401 Unauthorized` from ProGet during `dotnet restore` → secret not passed (`--secret id=proget_token,...` missing), or env var `PROGET_DOTNET_TOKEN` unset on the host, or `nuget.config` not in the build context (restore silently fell back to `nuget.org` and 401'd on a package that only exists in the private feed — check `dotnet restore -v n` output for which source was tried).
- `%PROGET_DOTNET_TOKEN%` appears literally in error messages → the env var wasn't set in the `RUN` scope. Confirm the `PROGET_DOTNET_TOKEN="$(cat /run/secrets/proget_token)"` prefix is on the same `RUN` line.
- `unable to get local issuer certificate` / TLS errors from the feed host → cert-install block is missing or ordered **after** `dotnet restore`. Move it earlier.
- `no such file or directory: /run/secrets/proget_token` → BuildKit not enabled, or `--secret` flag omitted. Set `DOCKER_BUILDKIT=1`.
- Token shows up in `docker history <image>` → someone used `ARG PROGET_DOTNET_TOKEN` / `ENV PROGET_DOTNET_TOKEN` instead of the secret mount. Switch to the pattern above and rebuild; consider the leaked image compromised if it was pushed.
- Works locally, fails in CI → CI runner is missing the `PROGET_DOTNET_TOKEN` secret in its environment, or uses an older Docker without BuildKit.
### ASP.NET Core architecture (guidelines, not dogma)
- Use ASP.NET Core MVC conventions to organize functionality (Controllers, Views, Models).
- Prefer clear domain models over generic key/value blobs.
- When building server-rendered web apps, Razor views are the default.
- JavaScript is allowed where it improves UX (e.g., fetch-based interactions).
