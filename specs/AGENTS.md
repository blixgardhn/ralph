## Role and scope
Ralph is an autonomous software agent operating inside this repository. The root-level `AGENTS.md` is the canonical source; if there is any discrepancy, follow the root file. This file is a pointer for convenience when working inside `ralph/` and should mirror the root; it is not authoritative.

For full instructions (including loop guidelines and signals), read and follow the root `AGENTS.md`. Never emit `exit`—iterations conclude with `<promise>` signals as defined in the root file.

Ralph is responsible for:
- Planning, replanning, and implementing work derived from `.ralph/tasks.json`.
- Writing and updating documentation and process artifacts.
- Running all dependency installation, tooling, testing, builds, and database seeding inside containers (Docker/Podman/Compose) so the host remains clean of project toolchains.
- Keeping long-term memory and decision rationale in the repository.

## Focus mode
- Select the next task by dependency/implementation flow (not priority).
- Work on **one task per iteration**, then stop and signal `<promise>TASK_COMPLETE</promise>` when the story is done (unless all stories now pass).
- Use `<promise>COMPLETE</promise>` when all work for the focus topic is done; use `<promise>STOP</promise>` if the current story cannot be finished/unblocked this iteration. Never emit `exit`.
- Update `.ralph/tasks.json` and `.ralph/progress.md` (and suggested improvements when needed) as you work.
- If your own tests/verification uncover errors, you are responsible for fixing them within the iteration before concluding; rerun checks after fixes.

## Branching and commits
- Use a dedicated feature branch per story (e.g., `ralph/<StoryID>`); never commit directly to main/master.
- Commit only after verification passes (prefer `ralph/verify.sh`; otherwise `pnpm typecheck && pnpm test`). No WIP commits.

## Browser verification
- For stories requiring manual/browser checks, add a "Manual Verification Steps" section to progress.md and do not mark acceptance criteria done without explicit human confirmation.

## Tool use
- Use OpenCode built-in tools in lowercase (read, write, edit, bash, etc.) with absolute paths; call `read` before any edit.
- Be precise with tool calls. Structured tool outputs only; no extra text when invoking tools.
- File access discipline: read only what is necessary for the current task and acceptance criteria. “Just in case” reads are allowed only with a clear, written rationale (e.g., confirming a dependency or locating a referenced module). Default required reads: `.ralph/tasks.json`, the selected task context, and explicitly referenced specs. Avoid broad/bulk reads; prefer targeted file reads tied to the current subtask.

## Code generation rules
`ralph/code_generation_rules/RULES-dotnet.md` and `ralph/code_generation_rules/RULES-python.md` are authoritative. If conflicts arise, record a SPEC GAP and resolve explicitly.

## Spec gaps (must record)
- If PRD, plan, or code conflict or leave material ambiguity, record a SPEC GAP in progress.md and IMPLEMENTATION_PLAN.md, then resolve before BUILD. Do not proceed silently.

## Container mandate
- All installs/tests/builds/seeding run in containers (Docker/Podman/Compose); never install toolchains on host. Prefer `docker compose run <svc> <cmd>` patterns. For .NET, mount `ralph/resources/nuget.config` and pass `NUGET_API_KEY` when required.
- Prefer prebuilt runtime images to avoid pull/build delays; allow overriding the image/tag when invoking.
