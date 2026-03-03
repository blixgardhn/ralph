Notes:

- This skill is the planning backbone of the Ralph Wiggum AI-agent methodology. All outputs (PRD, tasks.json, role docs, change ledger) must be auditable, reproducible, and junior-executable.
- Ensure PRDs include a documentation task when appropriate to update README.md with concise, descriptive content and a Mermaid diagram if feasible.
- Keep stories split small; add subtasks per story.
- Mini-PRD path: use for trivial scope (config tweak, rename, single-endpoint). Allow 3–4 tasks, one review iteration, but all other rules still apply. Document rationale for choosing mini-PRD in the PRD introduction.
- Per-role docs are mandatory (NNNN-role-<order>-<name>.md). Each must include: Inputs consumed, Decisions & changes, Task rewrites, Risks & open questions, Rationale.
- Change ledger and role sign-off checklist are required before finalizing; the Orchestrator (Role 7) owns these.
- branchName must include PRD ID: ralph/prd-<NNNN>-<slug>.
