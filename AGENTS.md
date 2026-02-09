# Ralph Agent (Lean)

## Overview

Lean loop to run a single-iteration agent until PRD stories are done. Progress is tracked only in `progress.md`.

## Command

```bash
./ralph.sh [--tool opencode|amp|claude] [--target-repo path] [max_iterations]
```

## Patterns
- When spinning up test containers, use the smallest base image that matches the stack under test; avoid heavier images when a minimal distro suffices.
- For images that need outbound network access, include the certificate install RUN block from `ralph/Dockerfile.dotnet`/`ralph/Dockerfile.template` to ensure proxy/interception certs are trusted.

## Key Files

- `ralph.sh` - thin loop runner
- `prompt.md` - instructions for the agent
- `prd.json.example` - PRD format example

## Guidelines

- Keep iterations small; one story per run
- Prefer containerized tooling; avoid host installs
- Append progress to `.ralph/progress.md`; keep `Codebase Patterns` concise but useful
- Update `prd.json` `passes` when a story is finished
- Logs live in `progress.md` only: note key files/functions, commands run (including tests), outcomes, follow-ups
- Append suggested improvements to the Ralph runner’s `.ralph/suggested_improvements.md` (kept in the runner repo, not the target repo)
- For each completed story: commit all changes (including prd.json and progress.md) with a clear story-specific message; push only when explicitly requested
- If required tools/entrypoints/tests or blocking code gaps exist, fix or create them first, then proceed with the story
- If a story cannot be completed (or unblocked) in the iteration, stop and exit without moving to another story
- Run targeted checks at minimum; run the full suite when finishing the PRD
- Update README only when user-facing behavior changes
- When running the software (any service/app), do so in a container unless explicitly told otherwise
