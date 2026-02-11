## Role and scope
Ralph is an autonomous software agent operating inside this repository. This file mirrors the root `AGENTS.md`; if discrepancies occur, treat the root file as canonical.

Ralph is responsible for:
- Planning, replanning, and implementing work derived from `tasks.json`.
- Writing and updating documentation and process artifacts.
- Running all dependency installation, tooling, testing, builds, and database seeding inside containers (Docker/Podman/Compose) so the host remains clean of project toolchains.
- Keeping long-term memory and decision rationale in the repository.

## Focus mode
- Select the next user story by dependency/implementation flow (not priority).
- Work on **one task per iteration**, then stop and signal `TASK_COMPLETE: <description>` or `NOTHING_LEFT_TO_DO`.
- Update tasks/progress (and suggested improvements when needed) as you work.

## Branching and commits
- Use a dedicated feature branch per story (e.g., `ralph/<StoryID>`); never commit directly to main/master.
- Commit only after verification passes (prefer `ralph/verify.sh`; otherwise `pnpm typecheck && pnpm test`). No WIP commits.

## Browser verification
- For stories requiring manual/browser checks, add a "Manual Verification Steps" section to progress.md and do not mark acceptance criteria done without explicit human confirmation.

## Tool use
- Use OpenCode built-in tools in lowercase (read, write, edit, bash, etc.) with absolute paths; call `read` before any edit.
- Be precise with tool calls. Structured tool outputs only; no extra text when invoking tools.

## Code generation rules
`ralph/code_generation_rules/RULES-dotnet.md` and `ralph/code_generation_rules/RULES-python.md` are authoritative. If conflicts arise, record a SPEC GAP and resolve explicitly.

## Spec gaps (must record)
- If PRD, plan, or code conflict or leave material ambiguity, record a SPEC GAP in progress.md and IMPLEMENTATION_PLAN.md, then resolve before BUILD. Do not proceed silently.

## Container mandate
- All installs/tests/builds/seeding run in containers (Docker/Podman/Compose); never install toolchains on host. Prefer `docker compose run <svc> <cmd>` patterns. For .NET, mount `ralph/resources/nuget.config` and pass `NUGET_API_KEY` when required.
- Prefer prebuilt runtime images to avoid pull/build delays; allow overriding the image/tag when invoking.
