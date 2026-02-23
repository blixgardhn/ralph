# Ralph Auto Loop - Meta Runner Notes

This file is for running Ralph in a meta `ralph.sh` context (e.g., editing or invoking the runner). Iteration-facing instructions live in `prompt.md`.

## Running the Ralph loop

Ralph (`ralph.sh`) orchestrates a loop of single-iteration agent runs until PRD stories are done; progress lives in `progress.md`.

### Command
```bash
./ralph.sh [--tool opencode|amp|claude] [--target-repo path] [max_iterations]
```

When invoked from a target repository that sits alongside this runner, call it as:
```bash
../ralph/ralph.sh [--tool opencode|amp|claude] [--target-repo path] [max_iterations]
```

### Patterns
- Use the smallest base image matching the stack under test; avoid heavy images.
- For images needing outbound access, include the cert-install RUN block from `ralph/resources/Dockerfile.dotnet` or `ralph/resources/Dockerfile.template`. Do not link directly to runner-only files; copy what you need into the target project.

### Key Files
- `ralph.sh` — loop runner
- `prompt.md` — iteration instructions (canonical for agent behavior)
- `.ralph/tasks.json` — PRD-backed tasks with `passes` status
- `.ralph/progress.md` — append-only learnings for iterations
- `tasks.json.example` — PRD format example

### Guidelines
- Keep iterations small; one story per run.
- Always run against a target repo (never the runner itself); set `--target-repo` explicitly when invoking from the runner.
- If `--target-repo` is omitted, Ralph uses the invocation working directory; ensure it is the intended target repo.
- Append progress to `.ralph/progress.md`; keep Codebase Patterns concise but useful.
- Update `tasks.json` passes when a story is finished.
- Logs live in `.ralph/progress.md` only: note key files/functions, commands run (including tests), outcomes, follow-ups.
- Append suggested improvements to the target repo’s `.ralph/suggested_improvements.md` (kept with the target, not the runner).
- If required tools/entrypoints/tests or blocking gaps exist, fix or create them first, then proceed.
- Update README when user-facing behavior changes.

## Canonical Iteration Rules

For the rules the agent follows during an iteration (task selection, containers, verification, promises, specs, branching, commits, error handling), see `prompt.md`.
