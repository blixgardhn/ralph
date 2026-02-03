---
name: prd
description: "Default to PRD + prd.json for any change request. Use when planning a feature, starting a project, or whenever the user asks to change code unless they explicitly say to implement without a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out, convert to ralph prd.json, change the code." 
user-invocable: true
---

# PRD + Ralph JSON Generator

Create a clear, actionable PRD in markdown and a synchronized `prd.json` for Ralph. Both outputs must describe the same stories, acceptance criteria, and ordering.

---

## The Job

1. Receive a feature or change request (assume PRD + prd.json is needed unless the user explicitly opts out)
2. Ask 3-5 essential clarifying questions (lettered options)
3. Generate the PRD in markdown
4. Generate the matching `prd.json`
5. Save both outputs; ensure they stay in sync (titles, IDs, order, acceptance criteria)
6. Keep tasks minimal and focused; split aggressively so each story fits in one iteration, but if two very small tasks fit naturally together and avoid reloading the same context, combine them into one story.
7. For each user story, include a short list of concrete subtasks to maximize planning before implementation starts; keep subtasks actionable and scoped to that story.
8. Add a dedicated documentation task when needed to produce or update `README.md`; keep it concise yet descriptive and include a Mermaid diagram where possible for system visualization.

**Important:** Do NOT implement the feature. Deliver specs only.

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

## Step 3: Ralph prd.json Structure

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
  "priority": 1,
  "passes": false,
  "notes": ""
    }
  ]
}
```

### Conversion and Sizing Rules
- Each story must fit in one Ralph iteration; split big items
- Order by dependencies: schema → backend → UI → summaries
- IDs sequential (US-001...), priorities follow order
- Every story has "Typecheck passes"; add "Tests pass" when relevant; add "Verify in browser using dev-browser skill" for UI
- `branchName` = `ralph/[feature-name-kebab-case]`
- Default to the smallest viable stories; avoid bundling unrelated work. Only combine tasks when they naturally belong together and stay within a single iteration.
- Include seed data requirements when acceptance tests need a preloaded database.
- When generating `prd.json`, actively split into smaller, narrowly scoped tasks to improve focus, testability, and per-iteration success.
- Add a concise `subtasks` array for each story in `prd.json` mirroring the markdown subtasks; keep them implementation-ready and limited to that story.

---

## Step 4: Outputs and Sync

- **Markdown PRD:** `.ralph/tasks/NNNN-prd-[feature-name].md` (next zero-padded number)
- **Ralph JSON:** `.ralph/prd.json` in repo root
- Keep titles, IDs, descriptions, acceptance criteria, and order identical between the markdown stories and JSON entries
- When new requirements arrive before all existing `userStories` have `passes: true`, append the new stories to both files and preserve all unfinished stories and their current `passes` values; do not rewrite or drop unpassed stories
- If an existing `.ralph/prd.json` belongs to a different feature and `.ralph/progress.md` has content, archive per runner convention before overwriting

### Archiving (when feature changes)
1. Read current `prd.json`
2. If `branchName` differs and `progress.md` has content beyond its header:
   - Create `archive/YYYY-MM-DD-[feature-name]/`
   - Copy `prd.json` and `progress.md` there
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
- [ ] Files saved to `.ralph/tasks/NNNN-prd-[feature].md` and `.ralph/prd.json` with matching content
