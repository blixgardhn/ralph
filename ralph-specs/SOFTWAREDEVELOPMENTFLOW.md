## Ralph Software Development Flow

1) **Select task**: Choose the next `passes: false` story from `.ralph/tasks.json` by dependency/implementation flow.
2) **Prep**: Read required specs (`AGENTS.md`, `prompt.md`, code generation rules). Ensure `.ralph/tasks.json` and `.ralph/progress.md` exist.
3) **Branch**: For PRD work, operate on the dedicated PRD branch (`ralph/prd-<id>`). Do not work on main/master.
4) **Implement**: Read only necessary files, make focused changes, and keep comments minimal.
5) **Verify (containerized)**: Run `ralph/verify.sh` when present; otherwise project-standard checks (e.g., `pnpm typecheck && pnpm test`).
6) **Commit**: After passing verification, commit changes (include task ID). For PRD iterations, make at least one commit when changes occurred.
7) **Update PRD artifacts**: Mark task `passes: true` when done and append an entry to `.ralph/progress.md` (include commands run and outcomes). Add runner improvement ideas to `.ralph/suggested_improvements.md` when relevant.
8) **Signal completion**: Emit `<promise>TASK_COMPLETE</promise>` (or `<promise>COMPLETE</promise>` when all tasks pass). Use `<promise>STOP</promise>` only after attempted remediation fails.
