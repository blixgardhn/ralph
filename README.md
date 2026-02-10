# Ralph

![Ralph](ralph.webp)

Ralph is an autonomous AI agent loop that runs AI coding tools (OpenCode by default, or [Amp](https://ampcode.com)/[Claude Code](https://docs.anthropic.com/en/docs/claude-code)) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.md`, and `prd.json`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read my in-depth article on how I use Ralph](https://x.com/ryancarson/status/2008548371712135632)

All project dependency installation, linting, testing, builds, and database seeding must run inside containers (Docker/Podman/Compose). Keep the host clean of project toolchains. For images that need outbound network access, include the certificate install RUN block from `ralph/resources/Dockerfile.dotnet`/`ralph/resources/Dockerfile.template` to ensure proxy/interception certs are trusted. Do not link directly to files in `ralph/resources`; copy the needed content into the target project because that code has no access to runner-only files (they are not secret).

## Prerequisites

- Docker or Podman with Compose support (all installs/tests/builds run in containers)
- One of the following AI coding tools installed and authenticated on the host (OpenCode is the default):
  - OpenCode CLI
  - [Amp CLI](https://ampcode.com)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- `jq` installed on the host (`brew install jq` on macOS)
- A git repository for your project

Project dependencies, linting, testing, builds, and database seeding must be executed via container entrypoints (e.g., `docker compose run` / `podman compose run`). Do not install project toolchains on the host.

## Setup

### Option 1: Copy to your project

Copy the ralph files into your project:

```bash
# From your project root
mkdir -p scripts/ralph
cp /path/to/ralph/ralph.sh scripts/ralph/

# Copy the prompt template:
cp /path/to/ralph/prompt.md scripts/ralph/prompt.md

chmod +x scripts/ralph/ralph.sh
```

Run project commands through container entrypoints (docker compose / podman compose). Keep project dependencies out of the host.

When you start a new PRD (or edit the current `prd.json`), Ralph auto-archives the previous run’s `prd.json` and `progress.md` into `archive/YYYY-MM-DD-<branch>/` and resets `progress.md` so each requirement set stays isolated.

### Option 2: Install skills globally (Amp/Claude)

Copy the skills to your Amp or Claude config for use across all projects:

For AMP
```bash
cp -r skills/prd ~/.config/amp/skills/
cp -r skills/ralph_prd ~/.config/amp/skills/
```

For Claude Code (manual)
```bash
cp -r skills/prd ~/.claude/skills/
cp -r skills/ralph_prd ~/.claude/skills/
```

### Configure Amp auto-handoff (recommended)

Add to `~/.config/amp/settings.json`:

```json
{
  "amp.experimental.autoHandoff": { "context": 90 }
}
```

This enables automatic handoff when context fills up, allowing Ralph to handle large stories that exceed a single context window.

## Workflow

### 1. Create a PRD

Use the PRD skill to generate a detailed requirements document:

```
Load the prd skill and create a PRD for [your feature description]
```

Answer the clarifying questions. The skill saves output to `tasks/prd-[feature-name].md`.

Before finalizing, take a high-level pass across all user stories: make sure they fit together, reorder them if dependencies or narrative flow suggest a better sequence, and promote any oversized subtasks into standalone stories, then re-run the overview and ordering.

### 2. Convert PRD to Ralph format

Use the Ralph skill to convert the markdown PRD to JSON:

```
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
```

This creates `prd.json` with user stories structured for autonomous execution.

### Quick start (minimal example)

```bash
# 1) Create PRD (interactive, uses prd skill)
Load the prd skill and create a PRD for "[your feature description]"

# 2) Convert to prd.json (ralph_prd skill)
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json

# 3) Run Ralph against your project repo
./ralph.sh --target-repo /path/to/your/repo
```

### 3. Run Ralph

```bash
# Using OpenCode (default)
./scripts/ralph/ralph.sh [max_iterations]

# Using Amp
./scripts/ralph/ralph.sh --tool amp [max_iterations]

# Using Claude Code
./scripts/ralph/ralph.sh --tool claude [max_iterations]
```

Default is 30 iterations. Use `--tool amp` or `--tool claude` to override the default OpenCode tool.

Ralph will:
1. Create a feature branch (from PRD `branchName`)
2. Pick the highest priority story where `passes: false`
3. Implement that single story
4. Run quality checks inside containers (typecheck, tests; no host toolchains)
5. Commit if checks pass
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.md`
8. Append improvement suggestions to the target repo’s `.ralph/suggested_improvements.md` (only when concrete learnings exist)
9. Repeat until all stories pass or max iterations reached

## Key Files

| File | Purpose |
|------|---------|
| `ralph.sh` | The bash loop that spawns fresh AI instances (supports `--tool opencode|amp|claude`, default OpenCode) |
| `prompt.md` | Prompt template for the AI tool |
| `prd.json` | User stories with `passes` status (the task list) |
| `prd.json.example` | Example PRD format for reference |
| `progress.md` | Append-only learnings for future iterations |
| `suggested_improvements.md` | Suggestions logged after each iteration to refine the loop (lives in the target repo) |
| `skills/prd/` | Skill for generating PRDs (works with Amp and Claude Code) |
| `skills/ralph_prd/` | Skill for converting PRDs to JSON (works with Amp and Claude Code) |

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** (OpenCode/Amp/Claude Code) with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.md` (learnings and context)
- `prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window. If a task is too big, the LLM runs out of context before finishing and produces poor code.

Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### AGENTS.md Updates Are Critical

After each iteration, Ralph updates the relevant `AGENTS.md` files with learnings. This is key because AI coding tools automatically read these files, so future iterations (and future human developers) benefit from discovered patterns, gotchas, and conventions.

Examples of what to add to AGENTS.md:
- Patterns discovered ("this codebase uses X for Y")
- Gotchas ("do not forget to update Z when changing W")
- Useful context ("the settings panel is in component X")

### Feedback Loops

Ralph only works if there are feedback loops:
- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

### Browser Verification for UI Stories

Frontend stories must include "Verify in browser using dev-browser skill" in acceptance criteria. Ralph will use the dev-browser skill to navigate to the page, interact with the UI, and confirm changes work.

### Stop Condition

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and the loop exits.

## Debugging

Check current state:

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat progress.md

# Check git history
git log --oneline -10
```

## Customizing the Prompt

After copying `prompt.md` to your project, customize it for your project:
- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

## Archiving

Ralph automatically archives previous runs when you start a new feature (different `branchName`). Archives are saved to `archive/YYYY-MM-DD-feature-name/`.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
