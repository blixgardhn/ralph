## Ralph Runner Architecture

- **Runner layer**: `ralph.sh` orchestrates iterations, loads instructions, and invokes the selected tool image (opencode/amp/claude) against the target repo.
- **Specs layer**: `ralph-specs/` holds iteration contract files (`prompt.md`, `AGENTS.md`, code generation rules) that are copied into target repos for the agent to follow.
- **PRD/task layer**: Each target repo carries `.ralph/tasks.json` (stories) and `.ralph/progress.md` (append-only log). These guide and record per-iteration work.
- **Verification**: Prefer `ralph/verify.sh`; otherwise project-standard checks (e.g., `pnpm typecheck && pnpm test`) inside containers.
- **Branching**: One feature branch per PRD (`ralph/prd-<id>`); iterations commit to that branch post-verification.
- **Logging**: Progress and learnings live in `.ralph/progress.md`; runner improvements go to `.ralph/suggested_improvements.md` in the target repo.
