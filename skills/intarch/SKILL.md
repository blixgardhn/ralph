---
name: intarch
description: "Create an architecture and design documentation repo for an integration service. Produces a full structured set of markdown documents covering system context, technical architecture, authentication, risk/privacy, and a reference glossary. Triggers on: create architecture repo, intarch, architecture documentation, design repo, document integration service."
user-invocable: true
---

# Integration Architecture Documentation Skill

> **DOCUMENTATION ONLY — DO NOT IMPLEMENT CODE.** This skill produces architecture and design documents. No source code, Dockerfiles, or CI pipelines are created here.

You are a solution architect creating structured documentation for a new integration service. The output is a git repo of markdown documents that stakeholders, architects, and developers can use as a shared basis for discussion and decision-making.

---

## What You Produce

A set of markdown files in the current directory:

| File | Audience | Content |
|------|----------|---------|
| `README.md` | All | Overview, role-based reading guide, technology choices, document index, open decisions, completion checklist |
| `SYSTEM-DESIGN.md` | Architects, stakeholders | System context, network zones, traffic flow, security model, compliance, privacy/GDPR basis, open design decisions |
| `TECHNICAL-ARCHITECTURE.md` | Solution architects, senior devs | Component/middleware architecture, technology choices, observability strategy, deployment model, configuration |
| `AUTHENTICATION-DESIGN.md` | Security architects, devs | Authentication model, token flows, identity responsibilities, audit responsibilities |
| `TECHNICAL-DETAILS.md` | Developers | Code patterns, configuration examples, edge cases, error handling, timeout chains |
| `REFERENCE.md` | All (especially onboarding) | Glossary, acronyms, organizations involved, end-to-end flow walkthrough, external links |
| `ROS-DPIA.md` | Privacy/security officers | Risk assessment and privacy impact assessment (stub with open items if not yet completed) |

---

## The Job

### Step 1 — Clarification

Ask the user these questions before writing anything. Wait for answers.

**A. What does this service do?**
One sentence: what is the integration, what systems does it connect, what problem does it solve?

**B. What are the key technical characteristics?**
Examples: reverse proxy, event bridge, API gateway, data transformer, authentication broker. What makes it architecturally interesting?

**C. Who are the key stakeholders/roles that will read these docs?**
Examples: solution architect, security officer, product owner, senior developer, junior developer, operations/forvaltning. (Default: all of the above.)

**D. What is the authentication model?**
How does the caller authenticate? How does the service authenticate to upstream? Any token bridging or trust domain crossing?

**E. What technology stack is planned or decided?**
Runtime, frameworks, hosting model (container, IIS, K8s), observability tools, deployment tooling. Write "unknown" for anything not yet decided.

**F. What org/domain context is relevant?**
Any regulatory requirements (GDPR, healthcare, finance), internal standards, existing similar systems to reference as patterns?

---

### Step 2 — Write the documents

Use the answers to produce all seven documents. Follow these rules:

#### README.md
- Start with a one-paragraph description of what the service does and why it exists.
- Include a Mermaid network/context diagram showing the service's position between callers and upstreams.
- Include a **role-based reading guide** table: each row is a stakeholder role, with a "start here" doc and a list of prioritized sections.
- Include a **technology choices** table (one row per dimension: runtime, framework, auth, observability, hosting, deployment, secrets).
- Include a **document index** table linking all documents with audience and one-line description.
- Include an **open decisions** numbered list — design choices not yet made.
- Include a **completion checklist** grouped by theme (security, auth, infrastructure, upstream integration) — items that must be resolved before production.

#### SYSTEM-DESIGN.md
- Section 1: Purpose and intended audience
- Section 2: System context — what problem does this solve, what systems are involved
- Section 3: Network zones — Mermaid diagram showing network placement, trust boundaries, firewall rules
- Section 4: Traffic flow — step-by-step numbered flow for the main request path
- Section 5: Upstream routing — how the service routes to upstreams (single vs. multi-upstream)
- Section 6: Security model — TLS termination, header stripping, allowed methods, token validation
- Section 7: Privacy/GDPR basis — what data is processed, legal basis, audit responsibilities
- Section 8: Compliance mapping — relevant regulations, standards, or org policies
- Section 9: Open design decisions — unresolved architectural questions with options and trade-offs

#### TECHNICAL-ARCHITECTURE.md
- Section 1: Purpose and intended audience
- Section 2: Component architecture — Mermaid diagram of the middleware/processing pipeline; table of components with responsibilities
- Section 3: Technology choices — rationale for each key choice
- Section 4: Observability — tracing, metrics, logging strategy; what is captured and where it goes
- Section 5: Deployment — hosting model, environment stages, configuration management, secrets delivery
- Section 6: Configuration — key config dimensions (upstream URL, auth settings, allowlist, timeouts)

#### AUTHENTICATION-DESIGN.md
- Section 1: Authentication model overview — Mermaid sequence diagram of the full auth flow
- Section 2: Inbound authentication — how callers authenticate to the service
- Section 3: Outbound authentication — how the service authenticates to upstreams
- Section 4: Token bridging — if trust domains are crossed, describe the token swap
- Section 5: Audit responsibilities — who logs what, which system is authoritative for audit

#### TECHNICAL-DETAILS.md
- Section 1: Purpose (implementation reference, not architecture)
- Section 2: Key code patterns — pseudocode or real code snippets for the most critical components
- Section 3: Configuration examples — annotated config file examples
- Section 4: Edge cases and error handling — what happens for each failure mode; expected HTTP status and error format
- Section 5: Timeout chain — end-to-end timeout budget from caller to upstream and back
- Section 6: Allowlist semantics (if applicable) — how endpoint matching works, precedence rules

#### REFERENCE.md
- Section 1: End-to-end flow — numbered walkthrough of what happens on a typical request, told as a narrative
- Section 2: Domain terms — glossary of domain-specific terms used in the documentation
- Section 3: Organizations and systems — brief description of each external party or system referenced
- Section 4: External links — curated list of relevant documentation, APIs, standards

#### ROS-DPIA.md
- If the user has risk/privacy information: write a structured risk assessment and privacy impact assessment.
- If not yet completed: write a stub with section headings, open items as checkboxes, and a note that this must be completed before production.
- Always include: threat model summary, data classification, privacy basis, conclusion/approval section.

---

### Step 3 — Document quality rules

- Every document starts with a status line: `**Status:** Living document — basis for discussion` and a `**Last updated:** <date>` line.
- Every major section has a `> **Relevant for:** <role list>` callout so readers can skip irrelevant sections.
- Cross-link documents — each doc references the others at the top under its Purpose section.
- Use Mermaid diagrams for architecture, flows, and network zones. Style nodes with fill/stroke colors for clarity.
- Use tables for: technology choices, document index, middleware pipeline, role reading guides.
- Open decisions and checklist items are numbered lists or checkboxes — not prose paragraphs.
- Write in English unless the user has written their description in another language, in which case mirror that language.
- Documents are intended as **basis for discussion**, not final specifications — say so explicitly in the README.

---

### Step 4 — Commit

After writing all files, stage and commit them:

```bash
git add .
git commit -m "Add architecture documentation for <service name>"
```

If the repo has no initial commit yet, initialize it first:

```bash
git init
git add .
git commit -m "Initial architecture documentation for <service name>"
```

---

## Example reference

The `intarch-komjour-proxy` repo is a good example of the target structure and quality level — a .NET reverse proxy bridging internal (Keycloak M2M) and external (HelseID) auth domains for a Norwegian healthcare integration. Use it as a reference for tone, detail level, and Mermaid diagram style if helpful.
