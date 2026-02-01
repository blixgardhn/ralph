# Ralph Agent (Lean)

## Overview

Lean loop to run a single-iteration agent until PRD stories are done. Progress is tracked only in `progress.md`.

## Command

```bash
./ralph.sh [--tool opencode|amp|claude] [max_iterations]
```

## Key Files

- `ralph.sh` - thin loop runner
- `prompt.md` - instructions for the agent
- `prd.json.example` - PRD format example

## Patterns

- Keep iterations small; one story per run
- Prefer containerized tooling; avoid host installs
- Append progress to `progress.md`; keep `Codebase Patterns` concise but useful
- Update `prd.json` `passes` when a story is finished
- Logs live in `progress.md` only: note key files/functions, commands run (including tests), outcomes, follow-ups
- If required tools/entrypoints/tests or blocking code gaps exist, fix or create them first, then proceed with the story
