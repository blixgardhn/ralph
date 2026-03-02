## Project Flow (bottom-up, MVP-first)

1) **Plan (lightweight)**: Capture requirements in PRD/tasks with clear acceptance criteria. Prefer thin vertical slices that can ship as an MVP each iteration.
2) **Architecture (just-enough)**: Pick a fitting style (layered, services, event-driven) and sketch minimal module boundaries to support the current slice.
3) **Branching**: Create one feature branch per PRD (`ralph/prd-<id>`); keep all iterations for that PRD on the same branch.
4) **Implement bottom-up**: Build foundations first (domain/data contracts, adapters), then wire upward. Keep each slice self-contained and reviewable.
5) **MVP each iteration**: Aim to produce a runnable, non-breaking MVP every iteration. If a feature spans iterations, ensure the build and tests stay green and guard incomplete paths behind flags or stubs.
6) **Verify (containerized)**: Run project-standard checks (`ralph/verify.sh` or `pnpm typecheck && pnpm test`, etc.) inside containers; fix and rerun until green.
7) **Commit**: After passing verification, commit changes with task/PRD identifiers. Make at least one commit per iteration when changes occur.
8) **Document**: Update PRD/task status, append progress notes (changes, commands run, outcomes, follow-ups).
9) **Review/Signal**: Surface manual verification steps when needed; prepare for merge without breaking main.
