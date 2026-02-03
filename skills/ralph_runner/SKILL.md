---
name: ralph_runner
description: "Run ../ralph/ralph.sh against the current repo without copying runner files. Triggers on: run ralph here, execute ralph, run ralph against this repo."
user-invocable: true
---

# Ralph Runner (sibling checkout)

Run Ralph from a sibling checkout (`../ralph`) against the current repo. Use when you are already at the target repo root and want Ralph to generate code there without importing/committing the runner files.

## Preconditions

- The Ralph repo is checked out at `../ralph` relative to the target repo root.
- `../ralph/ralph.sh` exists and is executable; it depends on `prompt.md` in the same directory.
- Do **not** copy or stage files from `../ralph` into the target repo. Only target-repo changes (including `.ralph/*` outputs) may be staged/committed.

## How to Run

1) Stay at the target repo root (the repo you want to modify).
2) Run Ralph with the sibling runner:
   ```bash
   DEST_REPO="$PWD" ../ralph/ralph.sh --tool opencode 1
   ```
   - Replace `1` to change max iterations if needed.
   - Pass `--tool amp` or `--tool claude` to switch tools.

## Notes

- Ralph writes metadata to `.ralph/` inside the target repo (e.g., `prd.json`, `progress.md`). These are safe to stage/commit if desired; do **not** add anything from `../ralph`.
- If `../ralph` is missing, stop and ask for the path to the Ralph checkout instead of copying files.
