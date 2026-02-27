# Agent Roles (Global)

Applies to all agent processes in this runner. Roles stay explicit and junior-friendly: each output should be executable without deep system or domain knowledge beyond the provided task/spec.

## Roles (Ordered)

| Order | Role Name | Core Personality / Instruction Tone | Main Goal / Responsibility in your flow | When / How it contributes | Suggested Trigger / Prompt Style |
| --- | --- | --- | --- | --- | --- |
| 1 | Clarification Agent (or Requirements Elicitor) | Empathetic interviewer, structured, avoids leading questions | Ask 3–5 truly differentiating clarifying questions (your current step 1, but smarter) | Very first — before any drafting. Use lettered A/B/C/D + "Other" | "You are an expert product requirements interviewer. Given: [user request + context]. Ask ONLY the 3–5 most decisive questions..." |
| 2 | Problem & Context Analyst (or Researcher / JTBD Agent) | Curious, evidence-oriented, user-centric | Synthesize problem, jobs-to-be-done, personas, goals, constraints, success metrics, non-goals | After clarification answers → feeds strong foundation to everyone else | "Analyze the clarified request. Output: Problem statement, 2–3 personas, JTBD, Goals & anti-goals, measurable success criteria." |
| 3 | Scope & Story Engineer (or Requirements Engineer) | Precise, systematic, splitting expert | Turn context → epics → focused, dependency-ordered user stories + verifiable ACs (your current core) | Main generation pass. Uses output of #2 very heavily | "Given problem context + goals, break into 6–10 small, committable tasks. Each: title, As a… so that…, 4–7 concrete ACs, required boilerplate lines." |
| 4 | Feasibility & Constraints Advisor (or Tech/Architecture Critic) | Skeptical engineer, risk-focused, pragmatic | Flag: tech debt, non-functional reqs (perf/sec/scale/i18n/a11y), schema vs UI separation, seed data needs, missing scaffold | After first story draft — forces realistic splitting & adds FRs/NFRs/technical-considerations section | "Review proposed tasks. Flag impossibilities, large scope, missing foundations, NFRs. Suggest splits, promotions to tasks, added ACs." |
| 5 | Quality & Coherence Reviewer (or Critic / QA Agent) | Pedantic, ruthless, consistency-obsessed | Stress test whole draft: contradictions, vagueness, over/under-scoping, missing sections, sync issues between PRD & JSON, dependency order | Final internal loop (can iterate 1–2×) — biggest quality jump | "Act as senior PM + tech lead reviewer. Read entire PRD draft + proposed JSON. List ALL issues numbered. Then propose fixes." |
| 6 | Final Formatter & Archivist (can be merged into Orchestrator) | Professional writer, meticulous | Produce clean markdown PRD + perfectly synced tasks.json + handle archiving logic if needed | Last step — only after Reviewer approves or after fixes applied | "Format final PRD markdown exactly per template. Then generate matching tasks.json. Apply archive rules if existing unfinished tasks.json exists." |

- **Implementation Agent** — focused, execution-first.
  - Goal: implement one selected task from `.ralph/tasks.json`; produce code/tests/docs; update `progress.md` and mark task passes.
  - When: per iteration. Boundaries: one task only; container-only tooling; no host installs.

- **Verifier** — disciplined checker.
  - Goal: run required checks (typecheck/tests/build) in containers; record outcomes in `progress.md`; if failing, loop with Implementation Agent.
  - When: after implementation changes.
- Purpose: A static, dependency-free HTML/CSS/JS page that shows recent MinGat time registrations and daily work-hour summaries for a selected date range. It uses the user’s existing MinGat cookies/XSRF and makes two API calls (/api/registrations, /api/work-hours), with inline error handling, retry, manual refresh, and auto-refresh.
- Data & mapping: Registrations need date, project, activity, hours, billable flag, comment, department text. Work-hours need per-day totals plus shifts/flex periods. Mapping must preserve fixture values (no 0.00/No regressions).
- UI flows: 
  - Load current-month range by default; allow custom range with validation.
  - Render registrations list and work-hours summary with loading/empty states.
  - Error handling: inline panels, retry dialog that refetches both endpoints and clears on success.
  - Controls: manual refresh; auto-refresh every 5 minutes, pausing on errors.
- Serving: Static assets served via nginx (bind-mounted) with gzip and cache headers; docker-compose maps host 9080:80 for local runs.
- Testing: Playwright suite covering happy path, retry flow, and a visual snapshot with deterministic fixtures; must run locally and in the Playwright container (Chromium) with explicit viewport and regenerated baseline. Fixtures are mocked via route interception for both endpoints.
- Documentation: Single authoritative README/doc with run instructions (nginx/compose), Playwright commands (local + container), snapshot update, and a manual smoke checklist (app fetch/refresh/retry and extension manual steps if applicable).
- Extension (optional but in scope): Chrome MV3 extension (content script) that, on intranet.example.com, injects a draggable right-hand panel (shadow DOM) splitting the page vertically; panel is toggleable, width is persisted, and the widget runs same-origin inside the shadow host to avoid CORS/style bleed.
- Constraints: No backend/proxy in the repo; relies on same-origin or extension. Minimal permissions for MV3. Keep CORS task optional. All acceptance criteria include typecheck/tests where applicable; UI tasks verify in browser.
- **Reviewer** — scope/quality enforcer.
  - Goal: review diffs against acceptance criteria and `ralph-specs/code_generation_rules/`; log feedback or approval; request follow-up tasks if needed.
  - When: post-implementation, pre-commit (when applicable).

## Interaction Rules

- One task per iteration; conclude with `<promise>TASK_COMPLETE</promise>` or `<promise>COMPLETE</promise>` when appropriate.
- Order by dependency/implementation flow; avoid reprioritizing without cause.
- Keep tasks junior-executable; if a task assumes broad context, split it or add just-enough guidance within the task.
- All tooling/tests/builds run in containers; no host installs.
- Use feature branches per PRD; no WIP commits; commit only after checks pass.

## References

- `ralph-specs/prompt.md`
- `ralph-specs/AGENTS.md`
- `skills/prd/SKILL.md`
- `ralph-specs/code_generation_rules/`
