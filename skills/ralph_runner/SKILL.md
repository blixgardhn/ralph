---
name: ralph_runner
description: "Run ralph.sh from the Ralph repo against a destination repo path. Triggers on: run ralph here, run ralph against, run ralph with dest, execute ralph." 
user-invocable: true
---

# Ralph Runner (Remote Destination)

Execute `ralph.sh` from the Ralph repo while pointing it at a destination repo provided as an argument.

---

## The Job

1. Require a destination repo path argument; resolve to an absolute path and verify it exists.
2. Set `DEST_REPO` to that path before invoking `ralph.sh` from the Ralph repo root.
3. Do not copy files; run in-place from the Ralph repo. Do not modify files in the Ralph repo—metadata, progress, and archives must stay under `DEST_REPO/.ralph`.
4. Preserve tool selection and iteration args; accept optional `--tool` and max iterations.
5. Stream output; do not detach. Report command, tool, destination path, and exit code.
6. Do not install host toolchains; if needed, instruct the user to run the containerized runner instead.

---

## Usage

```bash
# From Ralph repo root
export DEST_REPO=/abs/path/to/destination
./ralph.sh --tool opencode 10

# Or provide dest inline
DEST_REPO=/abs/path/to/destination ./ralph.sh --tool opencode 10
```

To run against another path without env export:

```bash
DEST_REPO="/abs/path/to/destination" ./ralph.sh --tool claude 5
```

---

## Output

Summarize:
- Tool used and iterations
- Destination path
- Command executed
- Exit code

Do not modify files outside the destination repo.
