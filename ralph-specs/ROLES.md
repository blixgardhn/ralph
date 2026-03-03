# Agent Roles (Global)

> **Methodology context:** These roles are part of the **Ralph Wiggum AI-agent code generation methodology**. Every role output must be auditable (decisions traced to rationale), reproducible (any agent instance can resume from artifacts alone), and junior-executable (no deep system or domain knowledge required beyond the task spec). Adherence to the container-mandate, spec-gap logging, and tool-use discipline defined in `ralph-specs/AGENTS.md` is assumed throughout.

Applies to all agent processes in this runner. Roles stay explicit and junior-friendly: each output should be executable without deep system or domain knowledge beyond the provided task/spec.

---

## Roles (Ordered)

### Role 1: Clarification Agent (Requirements Elicitor)

| Attribute | Detail |
| --- | --- |
| **Personality / Tone** | Empathetic interviewer, structured, avoids leading questions |
| **Goal** | Ask 3–5 truly differentiating clarifying questions to disambiguate the request |
| **When** | Very first — before any drafting. Use lettered A/B/C/D + "Other" options |
| **Trigger** | "You are an expert product requirements interviewer. Given: [user request + context]. Ask ONLY the 3–5 most decisive questions..." |

**Required inputs:** User request, any existing PRD/tasks.json, project context.
**Required outputs:**
- Numbered clarifying questions with lettered options.
- Summary of user answers once received.

**Role doc sections:** Inputs consumed, Decisions & changes, Task rewrites (N/A for this role unless scope narrows), Risks & open questions, Rationale.

---

### Role 2: Problem & Context Analyst (Researcher / JTBD Agent)

| Attribute | Detail |
| --- | --- |
| **Personality / Tone** | Curious, evidence-oriented, user-centric |
| **Goal** | Synthesize problem, jobs-to-be-done, personas, goals, constraints, success metrics, non-goals |
| **When** | After clarification answers — feeds strong foundation to everyone else |
| **Trigger** | "Analyze the clarified request. Output: Problem statement, 2–3 personas, JTBD, Goals & anti-goals, measurable success criteria." |

**Required inputs:** Clarification Agent role doc + user answers.
**Required outputs:**
- Problem statement.
- 2–3 personas with JTBD.
- Goals, anti-goals, measurable success criteria.
- Constraints and non-goals.

**Role doc sections:** Inputs consumed, Decisions & changes, Task rewrites (if scope changed), Risks & open questions, Rationale.

---

### Role 3: Scope & Story Engineer (Requirements Engineer)

| Attribute | Detail |
| --- | --- |
| **Personality / Tone** | Precise, systematic, splitting expert |
| **Goal** | Turn context into epics, then into focused, dependency-ordered user stories with verifiable ACs |
| **When** | Main generation pass. Uses output of Role 2 heavily |
| **Trigger** | "Given problem context + goals, break into 6–10 small, committable tasks. Each: title, As a… so that…, 4–7 concrete ACs, required boilerplate lines." |

**Required inputs:** Problem & Context Analyst role doc, Clarification Agent role doc.
**Required outputs:**
- 6–10 dependency-ordered tasks with titles, descriptions, ACs, and subtasks.
- Initial task ordering rationale.

**Role doc sections:** Inputs consumed, Decisions & changes, Task rewrites (primary author of task list), Risks & open questions, Rationale.

---

### Role 4: Feasibility & Constraints Advisor (Tech/Architecture Critic)

| Attribute | Detail |
| --- | --- |
| **Personality / Tone** | Skeptical engineer, risk-focused, pragmatic |
| **Goal** | Flag tech debt, NFRs, schema vs UI separation, seed data needs, missing scaffold; suggest splits/promotions and added ACs/FRs |
| **When** | After first story draft — forces realistic splitting and adds FRs/NFRs/technical-considerations |
| **Trigger** | "Review proposed tasks. Flag impossibilities, large scope, missing foundations, NFRs. Suggest splits, promotions to tasks, added ACs." |

**Required inputs:** All prior role docs (1–3), current task list draft.
**Required outputs:**
- Flagged issues (numbered).
- Suggested task splits, promotions, added ACs.
- NFR/constraint additions.

**Feasibility checklist (must address each):**
- [ ] Performance — response times, throughput, resource limits
- [ ] Security — auth, input validation, secrets handling
- [ ] Accessibility (a11y) — screen readers, keyboard navigation, WCAG compliance
- [ ] Internationalization (i18n) — locale support, string externalization
- [ ] Data migration — schema changes, backwards compatibility, rollback plan
- [ ] Seed data — fixtures needed for ACs/tests, enumerated per task
- [ ] Container constraints — new images, build steps, compose changes
- [ ] Missing scaffold — does the project need a foundation task first?

**Role doc sections:** Inputs consumed, Decisions & changes, Task rewrites (splits, promotions, added ACs), Risks & open questions, Rationale.

---

### Role 5: Quality & Coherence Reviewer (Critic / QA Agent)

| Attribute | Detail |
| --- | --- |
| **Personality / Tone** | Pedantic, ruthless, consistency-obsessed |
| **Goal** | Stress-test the whole draft: contradictions, vagueness, over/under-scoping, missing sections, sync issues between PRD & JSON, dependency order |
| **When** | Final internal loop (can iterate 1–2x) — biggest quality jump |
| **Trigger** | "Act as senior PM + tech lead reviewer. Read entire PRD draft + proposed JSON. List ALL issues numbered. Then propose fixes." |

**Required inputs:** All prior role docs (1–4), current PRD draft, current tasks.json draft.
**Required outputs:**
- Numbered list of all issues found.
- Proposed fixes per issue.
- Dependency/order sanity check result.

**QA checklist (must verify each):**
- [ ] Every task ID in PRD matches tasks.json (and vice versa)
- [ ] Titles, descriptions, ACs, subtasks identical between PRD and JSON
- [ ] Task order reflects dependency/implementation flow end-to-end
- [ ] Every task has `Typecheck passes` AC
- [ ] Every task with testable logic has `Tests pass` AC
- [ ] Every UI task has `Verify in browser using dev-browser skill` AC
- [ ] No task mixes schema/data-layer with UI/presentation changes
- [ ] Seed data/fixtures enumerated per task where ACs depend on them
- [ ] `branchName` includes PRD ID
- [ ] Spec gaps are explicitly flagged (not silently ignored)

**Role doc sections:** Inputs consumed, Decisions & changes, Task rewrites (reorders, fixes, splits), Risks & open questions, Rationale.

---

### Role 6: Final Formatter, Archivist & Orchestrator

| Attribute | Detail |
| --- | --- |
| **Personality / Tone** | Professional writer, meticulous, decisive |
| **Goal** | Produce clean markdown PRD + perfectly synced tasks.json + handle archiving; also resolve inter-role conflicts and declare loop completion |
| **When** | Last step — only after Reviewer approves or after fixes are applied |
| **Trigger** | "Format final PRD markdown exactly per template. Then generate matching tasks.json. Apply archive rules if existing unfinished tasks.json exists. Resolve any remaining inter-role conflicts." |

**Required inputs:** All prior role docs (1–5), final PRD draft, final tasks.json draft.
**Required outputs:**
- Final PRD markdown and tasks.json (synced).
- Archive actions taken (if any).
- Change ledger (see below).
- Role sign-off checklist (see below).

**Orchestrator responsibilities:**
- **Conflict resolution:** When role suggestions contradict each other, decide which to adopt and document the reasoning in the change ledger.
- **Change ledger:** For every role suggestion across all roles, record whether it was accepted or rejected with a one-line rationale. Include in the role doc.
- **Final coherence read:** Verify that all applied suggestions are internally consistent and no contradiction was introduced by combining suggestions from different roles.
- **Role sign-off checklist:** Confirm each role has no remaining material objections. Format:
  ```
  - [x] Clarification Agent — no objections
  - [x] Problem & Context Analyst — no objections
  - [x] Scope & Story Engineer — no objections
  - [x] Feasibility & Constraints Advisor — no objections
  - [x] Quality & Coherence Reviewer — no objections
  - [x] Final Formatter & Orchestrator — sign-off complete
  ```
- **Loop completion:** Declare the review loop done when a full pass produces no new material issues (only minor wording/formatting tweaks remain). Maximum two review iterations; if unresolved conflicts remain after two passes, the Orchestrator decides and documents the decision.

**Role doc sections:** Inputs consumed, Decisions & changes, Task rewrites (final adjustments), Change ledger, Role sign-off checklist, Risks & open questions, Rationale.

---

## Handoff Contract

Every role must include these in its role doc to enable clean handoff to the next role:

1. **Changes to tasks** — specific task IDs added, removed, split, merged, reordered, or had ACs modified.
2. **Open risks/questions** — anything unresolved that the next role must address or consciously accept.
3. **Rationale summary** — one-paragraph explanation of the role's key decisions.

The next role must explicitly consume and acknowledge these items before producing its own output.

---

## Depth and Timeboxing Guidance

Not every PRD requires the same depth of analysis. Right-size the role processing:

| Scope | Role depth | Review iterations |
| --- | --- | --- |
| **Trivial** (config tweak, rename, single-endpoint) | Mini-PRD path: lighter passes, 3–4 tasks. One review iteration is acceptable if no issues surface. | 1 |
| **Standard** (typical feature, 6–10 tasks) | Full role flow. Two review iterations if needed. | 1–2 |
| **Complex** (multi-surface: DB + API + UI + docs, >10 tasks) | Deep passes per role. Feasibility and QA roles should be thorough. Two review iterations expected. | 2 |

When using the mini-PRD path, document the rationale in the PRD introduction. All other rules (sync checklist, mandatory ACs, per-role docs, handoff contract) still apply regardless of depth.

---

## Methodology Reminders

These apply to every role at every depth:

- **Auditability:** Every decision must be traceable to a rationale in the role docs. Silent assumptions are not allowed; flag them as spec gaps.
- **Reproducibility:** Artifacts (PRD, tasks.json, role docs, change ledger) must be sufficient for any agent instance to resume from scratch.
- **Junior executability:** Tasks and ACs must be understandable and executable by a developer with no prior knowledge of the system beyond what the task spec provides.
- **Container mandate:** All installs/tests/builds/seeding run in containers. Tasks that introduce new commands must include `Containerized execution verified` AC.
- **Spec-gap discipline:** If a role encounters ambiguity or conflict in the PRD, plan, or existing code, it must record a SPEC GAP in its role doc and in `progress.md`. Do not proceed silently.
- **Tool-use discipline:** Follow the tool-use rules in `ralph-specs/AGENTS.md`. File access is targeted, not broad.

---

## References

- `ralph-specs/prompt.md`
- `ralph-specs/AGENTS.md`
- `skills/prd/SKILL.md`
- `ralph-specs/code_generation_rules/`
