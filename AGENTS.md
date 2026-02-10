# Ralph Agent (Lean)

## Overview
Ralph (`ralph.sh`) orchestrates a loop of fresh, single-iteration agent runs until PRD stories are done; the runner itself is not single-iteration. Progress is tracked only in `progress.md`.

## Command
```bash
./ralph.sh [--tool opencode|amp|claude] [--target-repo path] [max_iterations]
```

## Patterns
- Use the smallest base image matching the stack under test; avoid heavy images.
- For images needing outbound access, include the cert-install RUN block from `ralph/resources/Dockerfile.dotnet` or `ralph/resources/Dockerfile.template`. Do not link directly to runner files; copy the needed content into the target project because that code cannot access runner-only resources (they are not secret).

## Key Files
- `ralph.sh` — loop runner
- `prompt.md` — iteration instructions (see ralph/prompt.md for full content)
- `prd.json.example` — PRD format example

## Guidelines
- Keep iterations small; one story per run.
- Prefer containerized tooling; avoid host installs.
- Always run against a target repo (never the runner); set `--target-repo` explicitly if not running from inside the target.
- If `--target-repo` is omitted, Ralph uses the invocation working directory; ensure it is the intended target repo.
- Append progress to `.ralph/progress.md`; keep `Codebase Patterns` concise but useful.
- Update `prd.json` `passes` when a story is finished.
- Logs live in `progress.md` only: note key files/functions, commands run (including tests), outcomes, follow-ups.
- Append suggested improvements to the target repo’s `.ralph/suggested_improvements.md` (kept with the target).
- Commit completed stories (including PRD/progress); push only when explicitly requested.
- If required tools/entrypoints/tests or blocking gaps exist, fix or create them first, then proceed.
- If a story cannot be completed (or unblocked) in the iteration, stop and exit without moving to another story.
- Run targeted checks at minimum; run the full suite when finishing the PRD.
- Update README only when user-facing behavior changes.
- Run software in a container unless explicitly told otherwise.
