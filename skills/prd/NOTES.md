Notes:

- This skill is the planning backbone of the Ralph Wiggum AI-agent methodology. All outputs (PRD, tasks.json) must be auditable, reproducible, and junior-executable.
- Ensure PRDs include a documentation task when appropriate to update README.md with concise, descriptive content and a Mermaid diagram if feasible.
- Keep stories split small; add subtasks per story. Maximum 5 ACs (excluding boilerplate) and 6 subtasks per task.
- Mini-PRD path: use for trivial scope (config tweak, rename, single-endpoint). Allow 1–4 tasks, 4 essential roles (Clarification, Scope & Story, Codebase Pattern Analyst, Final Formatter), one review iteration. Document rationale in the PRD introduction.
- Roles run as a thinking process; outputs are captured in a "Role Decisions" section within the PRD (2–3 bullets per role). No separate role doc files.
- Change ledger and role sign-off checklist are included in the PRD; the Orchestrator (Role 8) owns these.
- branchName must include PRD ID: ralph/prd-<NNNN>-<slug>.
