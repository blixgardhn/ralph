---
name: ralph_container_runner
description: "Run ralph.sh inside a container with the Ralph repo mounted at /app and the caller's current working directory mounted at /app/dest_repo. Triggers on: run ralph, run ralph.sh, run ralph in container, containerized ralph, docker ralph, podman ralph."
user-invocable: true
---

# Ralph Container Runner

Run the Ralph harness via `docker compose` while mounting the Ralph repo to `/app` and the caller's destination repo to `/app/dest_repo`. This keeps host toolchains clean and ensures Ralph operates against the mounted destination repo using the in-container Ralph files.

---

## The Job

1. Prefer running `./ralph.sh` directly on the host; container use is optional. If you do use Docker, ensure Docker + Compose are available.
2. Set `DEST_REPO_HOST_PATH` to the absolute path of the destination repo on the host; set `RALPH_REPO_HOST_PATH` to the absolute path of the Ralph repo on the host. Export these env vars so Compose can mount them.
3. Optional container: use `RALPH_RUNNER_IMAGE` (default `ubuntu:22.04`) that already has `opencode` CLI available.
4. From the Ralph repo root, run `./ralph.sh [--tool opencode|amp|claude] [max_iterations]` on host, or `docker compose run --rm ralph-run /bin/bash -lc "/app/ralph.sh [--tool opencode|amp|claude] [max_iterations]"` in a container.
5. Compose mounts `/app` from `RALPH_REPO_HOST_PATH` (read-only) and `/app/dest_repo` from `DEST_REPO_HOST_PATH` (read/write) and sets `DEST_REPO=/app/dest_repo`.
6. Stream output; do not detach.
7. On completion, report the command, image used, mount points, and exit code (if using container).

---

## Example Command (Docker Compose)

```bash
export RALPH_REPO_HOST_PATH="/abs/path/to/ralph-repo"
export DEST_REPO_HOST_PATH="/abs/path/to/destination-repo"
# Optional: set RALPH_RUNNER_IMAGE if you use the container path
# export RALPH_RUNNER_IMAGE="ubuntu:22.04"

# Preferred: run on host
./ralph.sh --tool opencode 10

# Optional: run in container
docker compose run --rm ralph-run /bin/bash -lc "/app/ralph.sh --tool opencode 10"
```

---

## Output

Provide a concise summary:
- Runtime used (docker/podman)
- Image used
- Mounts (Ralph repo → /app, destination repo → /app/dest_repo)
- Command executed
- Exit code

Do not modify files outside `/dest_repo`. Do not install host toolchains.
