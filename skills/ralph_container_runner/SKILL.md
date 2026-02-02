---
name: ralph_container_runner
description: "Run ralph.sh inside a container with the Ralph repo mounted at /app and the caller's current working directory mounted at /app/dest_repo. Triggers on: run ralph, run ralph.sh, run ralph in container, containerized ralph, docker ralph, podman ralph."
user-invocable: true
---

# Ralph Container Runner

Run the Ralph harness inside a container while mounting the Ralph repo to `/app` and the caller's present working directory to `/app/dest_repo`. This keeps host toolchains clean and ensures Ralph operates against the mounted destination repo using the in-container Ralph files.

---

## The Job

1. Determine container runtime (Docker or Podman). Default to Docker; fall back to Podman if Docker is unavailable.
2. Choose an image: use `$RALPH_RUNNER_IMAGE` if set; otherwise default to `ubuntu:22.04` (caller must ensure `ralph.sh` dependencies are available in the image, e.g., `bash`, `git`, `jq`, AI CLI).
3. Mount the Ralph repo (this skill's repository root) read-only to `/app`.
4. Mount the caller's current working directory read/write to `/app/dest_repo`.
5. Set container working directory to `/app/dest_repo`.
6. Run `/app/ralph.sh [--tool opencode|amp|claude] [max_iterations]` inside the container shell (`/bin/bash -lc`), with `DEST_REPO=/app/dest_repo` set so Ralph reads/writes `.ralph` under the mounted destination. Pass through any required environment variables for the chosen AI tool (e.g., auth tokens) if the user provides them.
7. Stream output to the caller; do not detach.
8. On completion, report the command, image used, runtime (docker/podman), mount points, and exit code.

---

## Example Command (Docker)

```bash
docker run --rm -it \
  -v "$(pwd)":/app:ro \
  -v "${DEST_REPO:-$(pwd)}":/app/dest_repo \
  -w /app/dest_repo \
  ${RALPH_RUNNER_IMAGE:-ubuntu:22.04} \
  -e DEST_REPO=/app/dest_repo \
  /bin/bash -lc "/app/ralph.sh --tool opencode 10"
```

## Example Command (Podman)

```bash
podman run --rm -it \
  -v "$(pwd)":/app:ro \
  -v "${DEST_REPO:-$(pwd)}":/app/dest_repo \
  -w /app/dest_repo \
  ${RALPH_RUNNER_IMAGE:-ubuntu:22.04} \
  -e DEST_REPO=/app/dest_repo \
  /bin/bash -lc "/app/ralph.sh --tool opencode 10"
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
