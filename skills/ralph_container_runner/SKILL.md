---
name: ralph_container_runner
description: "Run ralph.sh inside a container with the Ralph repo mounted at /app and the destination repo mounted at /app/dest_repo. Triggers on: run ralph in container, docker ralph, containerized ralph, run ralph.sh with compose."
user-invocable: true
---

# Ralph Container Runner

Run the Ralph harness via `docker compose`, mounting the Ralph repo to `/app` (read-only) and the destination repo to `/app/dest_repo` (read/write). Metadata stays under the destination repo (`/app/dest_repo/.ralph`).

---

## The Job

1. Require Docker with Compose available.
2. From the destination repo, set `RALPH_DEST_REPO="$(pwd)"`, then `cd` to the Ralph repo to run Compose.
3. Export `RALPH_REPO_HOST_PATH` (absolute path to Ralph repo) and `OPENCODE_CONFIG_PATH` (path to host OpenCode config, e.g., `$HOME/.config/opencode`).
4. Optionally set `RALPH_RUNNER_IMAGE` (default `ralph-run:local` built from Dockerfile.ralph-run installing opencode via `curl -fsSL https://opencode.ai/install | bash`).
5. From the Ralph repo root, run `RALPH_ARGS="--tool opencode 10" docker compose up --abort-on-container-exit --force-recreate --remove-orphans`. Use `-d` **only** if you manage cleanup yourself.
6. Compose mounts `/app` from `RALPH_REPO_HOST_PATH` (read-only), `/app/dest_repo` from `RALPH_DEST_REPO` (read/write), and OpenCode config from `OPENCODE_CONFIG_PATH` read-only; sets `DEST_REPO=/app/dest_repo`.
7. Cleanup: on exit (including Ctrl-C), run `docker compose down --remove-orphans --volumes` from the Ralph repo to remove all started containers. Always perform this cleanup.
8. Stream output; do not detach unless you take responsibility for cleanup. Report command, image used, mounts, exit code.

---

## Example Command (Docker Compose)

```bash
export RALPH_REPO_HOST_PATH="/abs/path/to/ralph-repo"
export DEST_REPO_HOST_PATH="/abs/path/to/destination-repo"
# Optional: export RALPH_RUNNER_IMAGE="ghcr.io/your-org/ralph-run:latest"

docker compose run --rm ralph-run /bin/bash -lc "/app/ralph.sh --tool opencode 10"
```

---

## Output

Summarize:
- Runtime used (docker/podman)
- Image used
- Mounts (Ralph repo → /app, destination repo → /app/dest_repo)
- Command executed
- Exit code

Do not modify files outside `/app/dest_repo`. Do not install host toolchains.
