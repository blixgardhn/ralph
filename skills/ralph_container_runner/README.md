Run Ralph via Docker Compose. From the destination repo, set `RALPH_DEST_REPO=$(pwd)`, then `cd` to the Ralph repo. Mount `/app` (Ralph repo, read-only), `/app/dest_repo` (destination, read/write), and the host OpenCode config read-only. Optionally set `RALPH_RUNNER_IMAGE` (default build installs opencode via `curl -fsSL https://opencode.ai/install | bash`). Invoke:

```bash
docker compose run --rm ralph-run /bin/bash -lc "/app/ralph.sh --tool opencode 10"
```
