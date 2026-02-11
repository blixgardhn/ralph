#!/usr/bin/env bash
set -euo pipefail

PRD_FILE="${PRD_FILE:-.ralph/tasks.json}"
PROGRESS_FILE="${PROGRESS_FILE:-.ralph/progress.md}"

echo "[smoke_check] Checking PRD..."
ENFORCE_BRANCH=${ENFORCE_BRANCH:-false} ALLOW_CREATE_SUGGESTIONS=${ALLOW_CREATE_SUGGESTIONS:-false} PRD_FILE="$PRD_FILE" scripts/check_prd.sh

echo "[smoke_check] Validating progress.md header..."
if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "[smoke_check] progress.md not found at $PROGRESS_FILE" >&2
  exit 1
fi

header_ok=$(head -n 3 "$PROGRESS_FILE" | tr -d '\r' | grep -c -E '^## Codebase Patterns$|^# Ralph Progress Log$')
if [[ "$header_ok" -lt 2 ]]; then
  echo "[smoke_check] progress.md missing expected headers (## Codebase Patterns, # Ralph Progress Log)" >&2
  exit 1
fi

echo "[smoke_check] OK"
