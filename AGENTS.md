# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs AI coding tools (OpenCode by default, or Amp/Claude Code) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context.

## Commands

```bash
# Run Ralph with Amp (default)
./ralph.sh [max_iterations]

# Run Ralph with Claude Code
./ralph.sh --tool claude [max_iterations]
```

## Key Files

- `ralph.sh` - The bash loop that spawns fresh AI instances (supports `--tool amp` or `--tool claude`)
- `prompt.md` - Instructions given to the AI tool
- `prd.json.example` - Example PRD format
## Patterns

- Run all dependency installation, tooling, testing, builds, and database seeding inside containers (Docker/Podman/Compose); do not install project toolchains on the host
- Each iteration spawns a fresh AI instance (OpenCode/Amp/Claude Code) with clean context
- Memory persists via git history, `progress.md`, and `prd.json`
- Stories should be small enough to complete in one context window
- Keep each loop's working context intentionally small; split work so iterations stay focused and fast
- Verify each iteration's output before starting a new task; if blocked by tooling/external issues (e.g., Docker unavailable, missing commit/push permissions), exit the loop with a clear failure reason
- At the end of each iteration, verify the output; for coding tasks, run tests—if tests fail, restart the task; if you cannot fix within the iteration, exit with a clear failure reason
- Always update AGENTS.md with discovered patterns for future iterations
