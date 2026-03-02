## Software Development Flow (Ralph-generated projects)

1) **Plan**: Capture requirements in PRD/tasks; define acceptance criteria and constraints early.
2) **Architecture**: Choose a fitting style (layered, microservices, event-driven) and sketch module/service boundaries.
3) **Branching**: Create a dedicated feature branch per PRD (`ralph/prd-<id>`). Keep all iterations for that PRD on the same branch.
4) **Implement**: Work task-by-task; read only necessary files; keep changes focused and well-scoped.
5) **Verify (containerized)**: Run project-standard checks (`ralph/verify.sh` or `pnpm typecheck && pnpm test` etc.) inside containers.
6) **Commit**: After passing verification, commit changes (use task/PRD identifiers). Make at least one commit per iteration when changes occur.
7) **Document**: Update PRD/task status, append progress notes (what changed, commands run, outcomes, follow-ups).
8) **Signal/Review**: Prepare for review or merge; surface manual verification steps when applicable.
