# `ralph.sh`

High-level guide to the Ralph loop runner script used to orchestrate autonomous iterations against a target repository.

## Overview
- Launches repeated AI-driven coding iterations using a prompt template and PRD-derived tasks.
- Supports tools `opencode` (default), `amp`, and `claude`; OpenCode model defaults to `github-copilot/gpt-5.1-codex-max`.
- Enforces that work happens on a feature branch defined in `.ralph/tasks.json` (`branchName`); refuses to run on main/master or inside the runner repo itself.
- Archives PRDs when they change, initializes progress/suggestions files, and validates PRD structure before running.
- Builds the instruction prompt once at loop start; per-iteration, only the selected task JSON and recent progress are injected.
- Detects project language and includes only matching code generation rules.

## Usage
```bash
# From the runner directory
./ralph.sh [--tool opencode|amp|claude] [--host-mode] [--target-repo /path/to/repo] [max_iterations]
```

- `--tool` / `--tool=<name>`: choose the AI tool (default `opencode`).
- `--host-mode`: skip container wrapping; run tools, tests, and builds directly on the host.
- `--target-repo` / `--target-repo=<path>`: target repository root containing `.ralph/` files. Defaults to the current working directory. Must not be the runner repo.
- `--opencode-model` / `--opencode-model=<model>`: override the OpenCode model.
- Positional integer: maximum iterations to run (default `30`).

## What the script enforces
- **Prereqs**: `git` for branch checks and `jq` to read PRD metadata. Exits early if missing.
- **Prompt + PRD presence**: requires `prompt.md` in the runner and `.ralph/tasks.json` in the target repo (via `require_prd_file`).
- **Branch discipline**: reads `branchName` from the PRD and switches to (or creates) that branch; disallows main/master.

## Iteration flow
1) Builds the static prompt once at startup (instructions + language-specific rules).
2) Prints iteration header and selects the next pending task (sorted by dependency/flow).
3) Extracts the full task JSON and recent progress entry.
4) Injects them into the static prompt via `{{SELECTED_TASK}}` and `{{LAST_PROGRESS_ENTRY}}` placeholders.
5) Pipes the assembled prompt to the selected tool (`opencode run`, `amp`, or `claude`).
6) Captures output to detect `<promise>COMPLETE</promise>` or `<promise>STOP</promise>`; records suggestions via `prd_utils.sh` helpers.
7) After each iteration, counts remaining tasks and continues until a stop/complete promise is emitted or max iterations is reached.

## Key behaviors and paths
- Resolves `PROMPT_FILE` to `prompt.md` in the runner; PRD/progress paths are configured via `prd_utils.sh` based on `--target-repo`.
- Detects project language from target repo files (`.csproj`/`.sln` for .NET, `pyproject.toml`/`requirements.txt` for Python, `package.json` for Node). Falls back to including all rules if detection is ambiguous.
- Archives old PRDs when the current one changes before starting a run (see `archive_prd_if_changed` in `prd_utils.sh`).
- Initializes `.ralph/progress.md` and `.ralph/suggested_improvements.md` in the target repo if absent (never writes inside `RALPH_ROOT`).
- Exits with clear errors when validation fails (invalid tool, missing PRD, target repo path invalid, branch enforcement issues).

## Quick start examples
- Default tool, current directory target, 30 iterations:
  ```bash
  ./ralph.sh
  ```
- Use Amp against a specific repo for 10 iterations:
  ```bash
  ./ralph.sh --tool amp --target-repo /path/to/project 10
  ```
- Host mode (skip containers):
  ```bash
  ./ralph.sh --host-mode --target-repo /path/to/project
  ```
- Run Claude Code with explicit target repo and default iterations:
  ```bash
  ./ralph.sh --tool claude --target-repo ~/dev/my-app
  ```
