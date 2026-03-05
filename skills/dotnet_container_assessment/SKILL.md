---
name: dotnet_container_assessment
description: "Assess a .NET solution/project for 12-Factor and org container-readiness; produce a gap/blocker report without making changes. Triggers on: evaluate dotnet solution, 12-factor review, container readiness check."
user-invocable: true
---

# .NET 12-Factor & Container Readiness Assessor

Purpose: Read-only checklist-driven assessment for a .NET solution/project against the 12-Factor App principles (per Red Hat’s summary at https://www.redhat.com/en/blog/12-factor-app) and the organization’s container readiness document. Outputs a concise report of gaps, blockers, and recommended remediation steps. Does **not** modify code or config.

## Inputs
- Required: path to solution/project root (or specific .sln/.csproj).
- Recommended: path/URL to the org container readiness doc (default to `docs/container-readiness.md` if present; otherwise ask for location; if provided, use `https://example.com/docs/DEVELOPMENT-GUIDELINES.md`).
- Optional context: target deployment environment(s), expected runtime image (ASP.NET vs worker), and hosting model (Kestrel only vs behind reverse proxy).

## Behavior
- Read-only: inspect files and configs; do not run formatters or apply patches.
- Prefer static inspection; only run lightweight commands if necessary (`dotnet --info`, `dotnet list package`, `dotnet sln list`). Avoid `dotnet restore/build/test` unless explicitly requested.
- Scope: .NET 6+ assumed unless specified; note if lower.

## What to Inspect
- Solution layout: `.sln`, `Directory.Build.*`, `Directory.Packages.props`, `global.json`, project SDK style, TargetFramework.
- Configuration: `appsettings.*`, `secrets.json` usage, environment variable overrides, connection strings, feature flags, key vault/secret providers.
- Dependencies: `PackageReference` versions, runtime roll-forward, self-contained vs framework-dependent, native deps.
- Logging/telemetry: console logging to stdout/stderr, structured logging, OpenTelemetry exporters, log levels controlled by env vars.
- Hosting & health: `Program.cs` startup, Kestrel config, health/readiness/liveness endpoints, graceful shutdown hooks, `IHostApplicationLifetime` usage.
- State & storage: stateless process, session/cache providers, temp/storage paths, distributed cache configuration.
- Processes & admin tasks: migrations, seed/init scripts, background services/HostedServices (retry, backoff, cancellation, idempotency).
- Build/release/run split: build artifacts, config transforms, container build args, entrypoints.
- CI/CD & tests: presence of unit/integration tests, test commands, coverage/config gating.
- Container assets: `Dockerfile`, `.dockerignore`, Helm/compose/k8s manifests, non-root user, healthcheck, port exposure, env var wiring, volume mounts.
- Security: HTTPS enforcement, certificates handling, data protection keys, secrets sourcing, vulnerable packages (high-level), supply chain (locked feeds/nuget.config).
- Observability: metrics/tracing endpoints, sampling, correlation IDs, request logging privacy.

## 12-Factor Checklist (align findings to Red Hat summary):
- Codebase, Dependencies, Config (env vars), Backing services, Build/Release/Run separation, Processes (stateless), Port binding, Concurrency, Disposability (graceful shutdown/fast start), Dev/prod parity, Logs (stdout/err), Admin tasks.

## Container Readiness Checklist (map to org K8s guidelines when provided):
- Base image & patch level, non-root execution, minimal layers.
- Healthcheck/readiness probes exposed and wired to K8s probes.
- Runtime configuration via env vars/secrets files; no secrets in repo; sensitive defaults absent.
- Logging to stdout/err; structured preferred; rotation delegated to platform.
- Networking: port exposure, HTTPS/offload expectations, reverse proxy compatibility.
- Storage: no writable state in container FS unless mounted; temp paths isolated.
- Start/stop: graceful shutdown, `TERM` handling, short start time; retry/backoff for externals.
- Observability: metrics/traces, app version/build info surfaced.
- Supply chain: locked feeds (`nuget.config`), deterministic restore, pinned SDK/runtime via `global.json`.
- K8s manifests/Helm: namespace assumptions, resource requests/limits, securityContext (non-root, fsGroup), probes, liveness/readiness, env/secret refs per the provided guidelines URL.

## Steps
1) Collect inputs (paths, env/runtime assumptions, container-readiness doc location). If doc missing, note as blocker and proceed with 12-Factor-only review.
2) Enumerate solution and projects (`dotnet sln list` or glob for `*.csproj`), note TargetFrameworks and SDK style.
3) Inspect configs (`appsettings.*`, `launchSettings.json`, environment-specific files) for env-var override patterns and secret leakage.
4) Review `Program.cs`/startup for hosting model, health endpoints, logging, graceful shutdown, background services, and port binding.
5) Scan `Dockerfile`/manifests for base image, non-root, healthcheck, env wiring, volumes, build args, trimming/AOT/self-contained choices, and build/release separation.
6) Check `.dockerignore`, `nuget.config`, `Directory.Packages.props`, `global.json` for supply-chain and deterministic build signals.
7) For tests/CI, locate test projects, commands, and any pipeline hints (GitHub Actions/Azure Pipelines). Do not run tests unless asked.
8) Summarize gaps, blockers, and risks mapped to 12-Factor and container-readiness items; prioritize by severity (blocker/major/minor).

## Output Format
Produce a markdown-style report (no file writes unless asked) with:
- Summary (1–3 bullets): readiness posture.
- Blockers: items that prevent containerization/deploy (cite files/lines when possible).
- Gaps/Recommendations: grouped by 12-Factor and container-readiness categories; include specific actions.
- Evidence: brief pointers to inspected files (e.g., `src/App/Program.cs:45` missing health checks).
- Missing Info: what was assumed or needs confirmation.

## Notes
- Do not modify files; read-only assessment.
- Keep commands minimal; avoid long-running restores/builds unless requested.
- If multiple services exist, assess each briefly and call out per-service deltas.
