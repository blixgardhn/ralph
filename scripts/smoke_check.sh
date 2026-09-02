#!/usr/bin/env bash
set -euo pipefail

PRD_FILE="${PRD_FILE:-.ralph/tasks.json}"
PROGRESS_FILE="${PROGRESS_FILE:-.ralph/progress.md}"

echo "[smoke_check] Checking PRD..."
ENFORCE_BRANCH=${ENFORCE_BRANCH:-false} PRD_FILE="$PRD_FILE" scripts/check_prd.sh

echo "[smoke_check] Validating progress.md header..."
if [[ ! -f "$PROGRESS_FILE" ]]; then
  # Ralph's init_progress_file() creates this lazily; preflight should not
  # halt on its absence. Auto-create the canonical two-header stub.
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  {
    echo "## Codebase Patterns"
    echo ""
    echo "# Ralph Progress Log"
  } > "$PROGRESS_FILE"
  echo "[smoke_check] Created missing $PROGRESS_FILE" >&2
fi

header_ok=$(head -n 3 "$PROGRESS_FILE" | tr -d '\r' | grep -c -E '^## Codebase Patterns$|^# Ralph Progress Log$')
if [[ "$header_ok" -lt 2 ]]; then
  echo "[smoke_check] WARN: progress.md missing expected headers (## Codebase Patterns, # Ralph Progress Log)" >&2
fi

echo "[smoke_check] OK"
