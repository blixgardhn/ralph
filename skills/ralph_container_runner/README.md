Run Ralph via Docker Compose. From the destination repo, set `RALPH_DEST_REPO=$(pwd)`, then `cd` to the Ralph repo. Mount `/app` (Ralph repo, read-only), `/app/dest_repo` (destination, read/write), and the host OpenCode config read-only. Choose `RALPH_BASE_IMAGE` per task (e.g., `mcr.microsoft.com/dotnet/sdk:8.0` for .NET); default is `debian:bookworm-slim`. Optionally set `RALPH_RUNNER_IMAGE` (default build installs opencode via `curl -fsSL https://opencode.ai/install | bash`). Invoke, and always clean up containers on exit (including Ctrl-C):

```bash
RALPH_ARGS="--tool opencode 10" RALPH_BASE_IMAGE=<image> docker compose up --build --abort-on-container-exit --force-recreate --remove-orphans
# On exit (or Ctrl-C):
docker compose down --remove-orphans --volumes
```
