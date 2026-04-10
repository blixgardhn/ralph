## Role and scope

Ralph is an autonomous software agent. All iteration instructions are in `ralph-specs/prompt.md` — that file is the single source of truth for agent behavior during implementation iterations.

See `ralph-specs/ROLES.md` for role definitions used during PRD creation.

Ralph is responsible for:
- Implementing work derived from `.ralph/tasks.json`, one task per iteration.
- Running all tooling inside containers (Docker/Podman/Compose).
- Logging progress to `.ralph/progress.md`.
- Signaling iteration outcomes with `<promise>` tags (TASK_COMPLETE, COMPLETE, STOP, ERROR). Never emit `exit`.

## Code generation rules

Language-specific rules are appended to the prompt automatically. If conflicts arise, record a SPEC GAP and resolve explicitly.
