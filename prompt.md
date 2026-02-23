# Ralph Auto Loop (Lean)

## Role
Run exactly one unchecked task from `.ralph/tasks.json` per invocation, chosen by dependency/implementation flow (not priority). Stay non-interactive: do the work, log, and finish. Keep context tight and log only in `.ralph/progress.md`. This prompt must align with `AGENTS.md` and `ralph/prompt.md` (root `AGENTS.md` is canonical).

## Preflight
- Ensure `.ralph/tasks.json` and `.ralph/progress.md` exist and are readable. If missing/malformed, stop and log a SPEC GAP.

## Steps
- Read `.ralph/tasks.json` and `.ralph/progress.md`. If all `passes: true`, reply `<promise>COMPLETE</promise>`. If you finish a task and others remain, reply `<promise>TASK_COMPLETE</promise>`. Otherwise pick the next `passes: false` task by dependency/flow and work only on it.
- Use containers for all tooling: `docker run --rm -v "$PWD":/work -w /work <image> <tool> ...` (e.g., `node:20`, `python:3.11`, `mcr.microsoft.com/dotnet/sdk`). For .NET, mount runner `ralph/resources/nuget.config` and pass `NUGET_API_KEY`.
- Run verification: prefer `ralph/verify.sh`; if absent, run `pnpm typecheck && pnpm test` (or repo-standard checks). Record commands/results.
- Keep file reads minimal and purposeful: default to `.ralph/tasks.json`, the current task’s referenced specs, and only files needed to execute the task. "Just in case" reads require a clear rationale (e.g., verifying a dependency or locating a referenced module); avoid broad scans.
- Implement the task across needed layers; add/update tests and docs when behavior changes.
- Update PRD: mark task `passes: true` in `.ralph/tasks.json`; append a log entry to `.ralph/progress.md`.
- Append actionable improvement notes (if any) to `.ralph/suggested_improvements.md`.
- Commit only after verification passes; use the task ID in the commit message. Push only when asked.
- If you cannot finish/unblock, reply `<promise>STOP</promise>` with a brief reason—do not switch tasks. Never emit `exit`.

## Progress Log Format (to `progress.md`)
```
## [ISO timestamp] - [Story ID]
- What you changed (key files/functions)
- Checks/tests (commands + result)
- Notes (patterns, gotchas, follow-ups)
---
```

## Constraints
- Keep changes minimal and focused; one story per run. Add inline comments only for non-obvious logic; update README when user-facing behavior changes.
- If your own tests/verification uncover errors, fix them before concluding the iteration and rerun the checks.
