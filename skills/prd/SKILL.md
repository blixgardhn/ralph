---
name: prd
description: "Default to PRD + tasks.json for any change request. Use when planning a feature, starting a project, or whenever the user asks to change code unless they explicitly say to implement without a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out, convert to ralph tasks.json, change the code." 
user-invocable: true
---

# PRD + Ralph JSON Generator

> **Methodology:** This skill is the planning backbone of the **Ralph Wiggum AI-agent code generation methodology**. Every output must be auditable (decisions traced to rationale), reproducible (any agent instance can resume from artifacts alone), and junior-executable (no deep system or domain knowledge required beyond the task spec). Adherence to container-mandate, spec-gap logging, and tool-use discipline defined in `ralph-specs/AGENTS.md` is assumed throughout.

> **PLANNING ONLY — DO NOT IMPLEMENT.** This skill produces specs (PRD markdown + `tasks.json`). Implementation happens later in separate Ralph iterations, each run by a fresh agent instance with clean context. Starting to code during PRD creation breaks the methodology: it conflates planning with execution, pollutes the planning context, and produces work that cannot be reviewed before implementation begins. If the user asks you to "also implement" or "start coding," decline and explain that implementation is a separate phase.

Create a clear, actionable PRD in markdown and a corresponding `.ralph/tasks.json` for Ralph. Tasks in the JSON exist to support and realize the requirements in the PRD; a single requirement may need multiple tasks to be fully implemented.

---

## The Job

1. Read and apply `ralph-specs/ROLES.md`; run the full role flow while planning:

   **Role execution (in order):**
   - **Clarification Agent:** ask 3–5 decisive lettered questions (A/B/C/D + Other) to disambiguate.
   - **Problem & Context Analyst:** synthesize problem, personas, JTBD, goals, constraints, success metrics, non-goals.
   - **Scope & Story Engineer:** break into 6–10 small, committable, dependency-ordered tasks with concrete ACs/boilerplate.
   - **Feasibility & Constraints Advisor:** flag NFRs, tech debt, seed data, scaffold gaps; suggest splits/promotions and added ACs/FRs.
   - **Codebase Pattern Analyst:** read the target codebase to identify conventions, patterns, and relevant files; populate `keyFiles` and `implementationNotes` for every task so iteration agents skip file discovery and start implementing immediately.
   - **Quality & Coherence Reviewer:** stress-test PRD draft + JSON for contradictions, vagueness, ordering, and completeness of requirement coverage; list fixes. Verify every task has `keyFiles` and `implementationNotes` populated.
   - **Domain Expert:** validate domain accuracy — correct terminology, complete workflows, realistic edge cases, and ACs that reflect real-world usage in the problem space.
   - **Final Formatter & Archivist:** produce final PRD markdown + `.ralph/tasks.json`; apply archive rules if prior tasks exist.

   **Review loop:**
   - After the initial pass, each role reviews the PRD draft and task list. Each role may rewrite the task list as needed (reorder, add, remove, split, merge, or rewrite tasks) to improve clarity, feasibility, and junior executability.
   - Iterate until a full pass produces no new material issues (only minor wording/formatting tweaks remain). This is the **loop stop condition**.
   - Maximum two review iterations; if unresolved conflicts remain after two passes, the Orchestrator (see below) decides.

   **Orchestrator / Arbiter:**
   - The Final Formatter & Archivist also acts as Orchestrator. Responsibilities:
     - Resolve conflicts between roles when suggestions contradict each other.
     - Maintain a **change ledger**: for every role suggestion, record whether it was accepted or rejected, with a one-line rationale.
     - Perform a final coherence read to ensure all applied suggestions are internally consistent.
     - Declare loop completion and produce a **role sign-off checklist** confirming each role has no remaining objections.

   **Per-role document requirements:**
   - Each role must produce a brief role-specific document stored alongside the PRD in `.ralph/prds/`.
    - **Filename pattern:** `NNNN-role-<order>-<name>.md` (e.g., `0001-role-1-clarification.md`, `0001-role-7-domain-expert.md`). The order prefix preserves sequence and avoids collisions with the primary PRD file (`NNNN-prd-[feature-name].md`).
   - **Required sections in each role doc:**
     1. **Inputs consumed** — which prior role docs and user inputs were read.
     2. **Decisions & changes** — what was decided or changed in the PRD/tasks.
     3. **Task rewrites** — specific task additions, removals, splits, merges, or reorderings.
     4. **Risks & open questions** — unresolved issues handed to the next role.
     5. **Rationale** — why each decision was made (audit trail for the methodology).
   - Every subsequent role must read all prior role documents as inputs to its own output.

2. Generate the PRD in markdown using clarified inputs and the role outputs.
3. Generate the matching `.ralph/tasks.json` (omit any priority fields; task selection is done per iteration by dependency/implementation flow).
4. After the first full pass, review the PRD task list and split any broad tasks into focused jobs that are deterministic, testable, individually committable, and small enough for a junior developer to pick up without needing deep system or domain knowledge.
5. Save both outputs; ensure every task in `tasks.json` traces back to one or more functional requirements in the PRD and that all requirements are covered by at least one task.
6. Keep tasks minimal and focused; split aggressively so each task fits in one iteration, but if two very small tasks fit naturally together and avoid reloading the same context, combine them into one task.
7. Ensure the PRD depth and task list size mirror the complexity of the application being specified; right-size scope so complexity is captured without over- or under-splitting.
8. Before finalizing the PRD, take a high-level pass over all tasks to ensure they fit together coherently and reorder them based on dependencies and implementation flow; the order must make sense end-to-end.
9. During that pass, if any subtasks are large enough to stand alone, promote them to tasks, then re-run the overview and reorder as needed.
10. After creating tasks, sanity-check each one for clarity and scope: a non-expert should be able to execute it without learning more of the system or domain than necessary.
11. If the project lacks a minimal scaffold (or more), include an initial task to create it so later tasks have a foundation.
12. For each task, include a short list of concrete subtasks to maximize planning before implementation starts; keep subtasks actionable and scoped to that task.
13. Add a dedicated documentation task when needed to produce or update `README.md`; keep it concise yet descriptive and include a Mermaid diagram where possible for system visualization.

### Mini-PRD Path (Trivial Scope)

When the scope is truly tiny (e.g., a config tweak, a single-file rename, a one-endpoint addition):
- Allow 3–4 tasks minimum; still require boilerplate ACs and the role loop (one pass is acceptable if no issues surface).
- Document the rationale for choosing the mini-PRD path in the PRD introduction.
- All other rules (requirement coverage checklist, mandatory ACs, per-role docs) still apply.

### Methodology-Specific AC Constraints

Every task **must** include the following mandatory acceptance criteria where applicable:
- `Typecheck passes` — always required.
- `Tests pass` — required when the task includes testable logic.
- `Verify in browser using dev-browser skill` — required for any task with UI changes.
- `Spec gaps recorded and resolved` — required when the task touches ambiguous or underspecified areas.
- `Containerized execution verified` — required when the task introduces new build/run/test commands.

Hard constraints on task composition:
- **Schema + UI in one task is banned.** Separate data-layer changes from presentation changes.
- **Seed data/fixtures must be enumerated per task** when ACs depend on preloaded data; do not leave seed data as an afterthought.
- **Documentation task required** when user-facing behavior changes (e.g., new CLI flags, API endpoints, UI flows).

**Important:** Do NOT implement the feature. Deliver specs only. No code changes, no file creation beyond the PRD and tasks.json artifacts, no "getting started" on the first task. Implementation is handled by separate Ralph iteration agents after the PRD is reviewed. This separation is fundamental to the methodology — planning and implementation are distinct phases run by different agent instances.

---

## Software Development Process - Overview

The software development process goes in stages and, with agile, parts of this flow loop while progressing toward the end goal.

### Software Delivery Flow (10 Steps)
- Idea → Capture the problem, goals, constraints, stakeholders, and success metrics.
- PRD → Write a concise PRD with scope, non-functional requirements, milestones, and risks; get stakeholder sign-off.
- Solution Design → Draft architecture, data model, API contracts, edge cases, and traceability back to PRD.
- Project Scaffolding → Generate repo structure, CI hooks, linters/formatters, env configuration, and secrets handling.
- Backlog & Plan → Break into tickets (features/tech tasks), estimate, prioritize, and define acceptance criteria per ticket.
- Implementation → Code in small branches/PRs, follow conventions, keep commits purposeful, and update docs as you go.
- Tests → Add/maintain unit, integration, and contract tests plus fixtures; aim for fast feedback locally and in CI.
- CI/CD → Ensure automated lint/test/build, artifacts, and gated merges; provision preview environments if applicable.
- Verification → Run end-to-end and non-functional tests (performance, security, accessibility); fix regressions; update changelog/release notes.
- Acceptance & Release → Demonstrate against PRD acceptance criteria, obtain sign-off, tag/release, and monitor post-release.

You must always understand what part of this flow your project is in, what the prerequisites are for each stage, and how tasks connect across phases.

---

## Step 1: Clarifying Questions

Ask only the critical gaps. Focus on Problem/Goal, Core Functionality, Scope/Boundaries, and Success Criteria.

Format questions with numbered prompts and A/B/C/D options, e.g.:

```
1. What is the primary goal of this feature?
   A. Improve user onboarding experience
   B. Increase user retention
   C. Reduce support burden
   D. Other: [please specify]

2. Who is the target user?
   A. New users only
   B. Existing users only
   C. All users
   D. Admin users only

3. What is the scope?
   A. Minimal viable version
   B. Full-featured implementation
   C. Just the backend/API
   D. Just the UI
```

Users can reply with codes like "1A, 2C, 3B".

---

## Step 2: PRD Structure (Markdown)

Sections:
1. Introduction/Overview — the feature and problem it solves
2. Goals — specific, measurable objectives
3. Tasks (formerly “user stories”) — each task must be one focused iteration
   - Title, Description ("As a [user], I want [feature] so that [benefit]"), Acceptance Criteria
   - UI tasks also require: "Verify in browser using dev-browser skill"
   - Always include: "Typecheck passes"; add "Tests pass" when logic is testable
4. Functional Requirements — numbered, explicit (FR-1, FR-2...)
5. Non-Goals — what is out of scope
6. Design Considerations (optional)
7. Technical Considerations (optional)
8. Success Metrics
9. Open Questions
10. Seed Data — datasets/fixtures needed to run acceptance tests or local flows

Task format:
```markdown
### T-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Verifiable criterion
- [ ] Another verifiable criterion
- [ ] Typecheck passes
- [ ] Tests pass (include when applicable)
- [ ] Verify in browser using dev-browser skill (UI stories)
```
**Important:**

* Acceptance criteria must be verifiable, not vague. "Works correctly" is bad. "Button shows confirmation dialog before deleting" is good.
* For any story with UI changes: Always include "Verify in browser using dev-browser skill" as acceptance criteria. This ensures visual verification of frontend work.

---

## Step 3: Ralph tasks.json Structure

```json
{
  "project": "[Project Name]",
  "branchName": "ralph/prd-<NNNN>-[feature-name-kebab-case]",
  "description": "[PRD-NNNN] [Feature description from PRD]",
  "tasks": [
    {
      "id": "T-001",
      "title": "[Task title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": ["Criterion 1", "Criterion 2", "Typecheck passes"],
      "subtasks": ["Subtask 1", "Subtask 2"],
      "keyFiles": ["src/routes/example.ts", "src/services/example.ts", "tests/example.test.ts (create new)"],
      "implementationNotes": "Follow the pattern in src/routes/users.ts for route + controller + test structure. Use the existing BaseService class for the service layer.",
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Conversion and Sizing Rules
- Target 6–10 tasks for a typical feature; never fewer than 4 unless the feature is truly tiny.
- Each task must fit in one Ralph iteration (~1–2 hours). If it needs backend + UI + docs, split.
- Split by dependency order: schema → backend/service/API → UI → validation/edge cases → docs/ops.
- If no scaffold exists, the first task should create a minimal one (or more) so downstream tasks have a base.
- If a task spans multiple boundaries (DB + API + UI) or has >4 acceptance criteria, split it.
- Schema+UI in one task is not allowed—separate data changes from presentation changes.
- IDs sequential (T-001...); task order follows dependency and implementation flow. Do not add priority fields—selection happens at runtime based on dependencies/flow.
- Every task has "Typecheck passes"; add "Tests pass" when relevant; add "Verify in browser using dev-browser skill" for UI; add "Spec gaps recorded and resolved" when touching ambiguous areas; add "Containerized execution verified" when introducing new build/run/test commands.
- `branchName` = `ralph/prd-<NNNN>-<feature-name-kebab-case>` (must include PRD ID for provenance).
- Include seed data requirements when acceptance tests need preloaded data.
- `subtasks`: every story lists 3–6 actionable subtasks scoped to that story only; if you cannot do that without crossing boundaries, split again.
- `keyFiles` (optional): array of file paths relevant to the task — files to read, create, or modify. Populated by the Codebase Pattern Analyst (Role 5). Paths that don't exist yet should include a `(create new)` suffix. These are hints, not guarantees; iteration agents should fall back to searching by filename stem if a listed path doesn't exist.
- `implementationNotes` (optional): concise guidance on how to implement — which patterns to follow, reference implementations in the codebase, naming conventions, test file locations. Populated by the Codebase Pattern Analyst (Role 5).

---

## Step 4: Outputs and Traceability

- **Markdown PRD:** `.ralph/prds/NNNN-prd-[feature-name].md` (next zero-padded number)
- **Ralph JSON:** `.ralph/tasks.json` in repo root
- **Role docs:** `.ralph/prds/NNNN-role-<order>-<name>.md` per role (1–8; see per-role document requirements above)
- Tasks exist to realize and support the PRD's functional requirements; a single requirement may need multiple tasks, and that is expected
- Every task must trace back to at least one functional requirement; every functional requirement must be covered by at least one task
- Task IDs, titles, and acceptance criteria in `tasks.json` are authoritative for implementation; the PRD provides the requirements context and rationale
- When new requirements arrive before all existing `tasks` have `passes: true`, append the new tasks to both files and preserve all unfinished tasks and their current `passes` values; do not rewrite or drop unpassed tasks
- If any `passes: false` tasks exist, do not archive the current `.ralph/tasks.json`; instead, append new tasks to it so unfinished work remains
- If an existing `.ralph/tasks.json` belongs to a different feature and `.ralph/progress.md` has content, archive per runner convention before overwriting (only when all tasks have `passes: true`)

### Requirement Coverage / QA Checklist (must pass before finalizing)

Run this checklist after producing both files:

- [ ] Every task in tasks.json traces back to at least one functional requirement in the PRD
- [ ] Every functional requirement in the PRD is covered by at least one task in tasks.json
- [ ] Task order reflects dependency and implementation flow
- [ ] Every task has `Typecheck passes` AC
- [ ] Every task with testable logic has `Tests pass` AC
- [ ] Every UI task has `Verify in browser using dev-browser skill` AC
- [ ] Seed data/fixtures are enumerated per task where ACs depend on them
- [ ] No task mixes schema/data-layer changes with UI/presentation changes
- [ ] Every task has `keyFiles` populated (may be empty array for greenfield scaffold tasks only)
- [ ] Every task has `implementationNotes` populated (may be brief for trivial tasks)
- [ ] `keyFiles` paths are plausible given the codebase structure
- [ ] `branchName` includes PRD ID: `ralph/prd-<id>-<feature-slug>`
- [ ] Role sign-off checklist is complete (all roles have no remaining objections)
- [ ] Change ledger is present and documents accepted/rejected suggestions with rationale

### Branch and Archive Naming

- `branchName` must include the PRD ID for provenance: `ralph/prd-<NNNN>-<feature-name-kebab-case>`.
- The PRD ID must also appear in the tasks.json `description` field to trace artifacts back to the methodology run.
- Archive rules: only archive when all tasks have `passes: true` and `branchName` differs from the new feature. Include the PRD ID in the archive directory name: `archive/YYYY-MM-DD-prd-<NNNN>-[feature-name]/`.

### Archiving (when feature changes)
1. Read current `tasks.json`
2. If `branchName` differs and `progress.md` has content beyond its header:
   - Create `archive/YYYY-MM-DD-prd-<NNNN>-[feature-name]/`
   - Copy `tasks.json`, `progress.md`, and all role docs for that PRD there
   - Reset `progress.md` header

---

## Writing for Junior Developers

Be explicit, avoid jargon, number requirements, and use concrete examples. Acceptance criteria must be testable, not vague.

---

## Final Checklist (both files must pass)

- [ ] **No implementation was performed** — only PRD markdown, tasks.json, and role docs were produced; no feature code was written or modified
- [ ] Clarifying questions asked and answered (lettered options)
- [ ] Tasks are small, ordered by dependency, and every functional requirement is covered by at least one task
- [ ] Every task has verifiable acceptance criteria with required boilerplate lines (typecheck, tests, browser, spec gaps, container as applicable)
- [ ] No task mixes schema/data-layer with UI/presentation changes
- [ ] Every task has `keyFiles` and `implementationNotes` populated (by Codebase Pattern Analyst)
- [ ] Seed data/fixtures enumerated per task where ACs depend on them
- [ ] Functional requirements are numbered; non-goals set boundaries
- [ ] Files saved to `.ralph/prds/NNNN-prd-[feature].md` and `.ralph/tasks.json`
- [ ] Per-role docs saved to `.ralph/prds/NNNN-role-<order>-<name>.md` with required sections
- [ ] `branchName` includes PRD ID (`ralph/prd-<NNNN>-<slug>`)
- [ ] Requirement coverage / QA checklist passed (see Step 4)
- [ ] Role sign-off checklist complete; change ledger present
- [ ] Methodology rationale documented if mini-PRD path was chosen

---

## Post-Completion Notification

After saving the PRD markdown and `.ralph/tasks.json`, send a Pushover notification to alert the user that the PRD is ready for review. Run this Bash command:

```bash
RALPH_ROOT="${RALPH_ROOT:-$(cd "$(dirname "$(find ../ralph -name ralph.sh -maxdepth 1 2>/dev/null | head -1)" 2>/dev/null)" && pwd)}"
if [ -n "$RALPH_ROOT" ] && [ -x "$RALPH_ROOT/scripts/notify.sh" ]; then
  "$RALPH_ROOT/scripts/notify.sh" "PRD Complete" "PRD and tasks.json have been generated and are ready for review." 0
fi
```

If `RALPH_ROOT` is not set or `scripts/notify.sh` does not exist, skip the notification silently. Do not fail the skill if the notification cannot be sent.

**Your job is done.** Do not proceed to implementation. The PRD and tasks.json are now ready for the user to review. Implementation will happen in separate Ralph iterations, each run by a fresh agent instance. Tell the user the PRD is ready and that they can start the implementation loop with `ralph.sh`.
