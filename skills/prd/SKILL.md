---
name: prd
description: "Default to PRD + tasks.json for any change request. Use when planning a feature, starting a project, or whenever the user asks to change code unless they explicitly say to implement without a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out, convert to ralph tasks.json, change the code." 
user-invocable: true
---

# PRD + Ralph JSON Generator

Create a clear, actionable PRD in markdown and a synchronized `tasks.json` for Ralph. Both outputs must describe the same stories, acceptance criteria, and ordering.

---

## The Job

1. Receive a feature or change request (assume PRD + tasks.json is needed unless the user explicitly opts out)
2. Ask 3-5 essential clarifying questions (lettered options)
3. Generate the PRD in markdown
4. Generate the matching `tasks.json` (omit any priority fields; task selection is done per iteration by dependency/implementation flow)
5. Save both outputs; ensure they stay in sync (titles, IDs, order, acceptance criteria)
6. Keep tasks minimal and focused; split aggressively so each story fits in one iteration, but if two very small tasks fit naturally together and avoid reloading the same context, combine them into one story.
7. Before finalizing the PRD, take a high-level pass over all stories to ensure they fit together coherently and reorder them based on dependencies and implementation flow; the order must make sense end-to-end.
8. During that pass, if any subtasks are large enough to stand alone, promote them to user stories, then re-run the overview and reorder as needed.
9. If the project lacks a minimal scaffold (or more), include an initial story to create it so later tasks have a foundation.
10. For each user story, include a short list of concrete subtasks to maximize planning before implementation starts; keep subtasks actionable and scoped to that story.
11. Add a dedicated documentation task when needed to produce or update `README.md`; keep it concise yet descriptive and include a Mermaid diagram where possible for system visualization.

**Important:** Do NOT implement the feature. Deliver specs only.

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
3. User Stories — each story must be one focused iteration
   - Title, Description ("As a [user], I want [feature] so that [benefit]"), Acceptance Criteria
   - UI stories also require: "Verify in browser using dev-browser skill"
   - Always include: "Typecheck passes"; add "Tests pass" when logic is testable
4. Functional Requirements — numbered, explicit (FR-1, FR-2...)
5. Non-Goals — what is out of scope
6. Design Considerations (optional)
7. Technical Considerations (optional)
8. Success Metrics
9. Open Questions
10. Seed Data — datasets/fixtures needed to run acceptance tests or local flows

Story format:
```markdown
### US-001: [Title]
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
  "branchName": "ralph/[feature-name-kebab-case]",
  "description": "[Feature description from PRD]",
  "userStories": [
    {
      "id": "US-001",
  "title": "[Story title]",
  "description": "As a [user], I want [feature] so that [benefit]",
  "acceptanceCriteria": ["Criterion 1", "Criterion 2", "Typecheck passes"],
   "subtasks": ["Subtask 1", "Subtask 2"],
   "passes": false,
   "notes": ""
    }
  ]
}
```

### Conversion and Sizing Rules
- Target 6–10 stories for a typical feature; never fewer than 4 unless the feature is truly tiny.
- Each story must fit in one Ralph iteration (~1–2 hours). If it needs backend + UI + docs, split.
- Split by dependency order: schema → backend/service/API → UI → validation/edge cases → docs/ops.
- If no scaffold exists, the first story should create a minimal one (or more) so downstream tasks have a base.
- If a story spans multiple boundaries (DB + API + UI) or has >4 acceptance criteria, split it.
- Schema+UI in one story is not allowed—separate data changes from presentation changes.
- IDs sequential (US-001...); story order follows dependency and implementation flow. Do not add priority fields—selection happens at runtime based on dependencies/flow.
- Every story has "Typecheck passes"; add "Tests pass" when relevant; add "Verify in browser using dev-browser skill" for UI.
- `branchName` = `ralph/[feature-name-kebab-case]`.
- Include seed data requirements when acceptance tests need preloaded data.
- `subtasks`: every story lists 3–6 actionable subtasks scoped to that story only; if you cannot do that without crossing boundaries, split again.

---

## Step 4: Outputs and Sync

- **Markdown PRD:** `.ralph/prds/NNNN-prd-[feature-name].md` (next zero-padded number)
- **Ralph JSON:** `.ralph/tasks.json` in repo root
- Keep titles, IDs, descriptions, acceptance criteria, and order identical between the markdown stories and JSON entries
- When new requirements arrive before all existing `userStories` have `passes: true`, append the new stories to both files and preserve all unfinished stories and their current `passes` values; do not rewrite or drop unpassed stories
- If any `passes: false` stories exist, do not archive the current `.ralph/tasks.json`; instead, append new tasks to it so unfinished work remains
- If an existing `.ralph/tasks.json` belongs to a different feature and `.ralph/progress.md` has content, archive per runner convention before overwriting (only when all stories have `passes: true`)

### Archiving (when feature changes)
1. Read current `tasks.json`
2. If `branchName` differs and `progress.md` has content beyond its header:
   - Create `archive/YYYY-MM-DD-[feature-name]/`
   - Copy `tasks.json` and `progress.md` there
   - Reset `progress.md` header

---

## Writing for Junior Developers

Be explicit, avoid jargon, number requirements, and use concrete examples. Acceptance criteria must be testable, not vague.

---

## Final Checklist (both files must pass)

- [ ] Clarifying questions asked and answered (lettered options)
- [ ] Stories are small, ordered by dependency, and mapped 1:1 between markdown and JSON
- [ ] Every story has verifiable acceptance criteria with required boilerplate lines
- [ ] Functional requirements are numbered; non-goals set boundaries
- [ ] Files saved to `.ralph/prds/NNNN-prd-[feature].md` and `.ralph/tasks.json` with matching content
