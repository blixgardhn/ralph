### Private NuGet feed (.NET) — ALWAYS REQUIRED

**Every .NET container must mount `nuget.config` and forward the feed env vars. Every `dotnet restore`/`dotnet build` command must do the same. No exceptions.** Skipping this means private packages won't resolve and the build fails.

The `nuget.config` at `$RALPH_ROOT/ralph-specs/resources/nuget.config` uses env var placeholders — if `NUGET_PRIVATE_FEED_URL` is empty the private feed entry is a no-op and builds fall back to nuget.org. Always mount it.

See the .NET rules for the exact `docker run` and `docker-compose.yml` patterns.
