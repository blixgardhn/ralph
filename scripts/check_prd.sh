#!/usr/bin/env bash
set -euo pipefail

PRD_FILE="${PRD_FILE:-.ralph/tasks.json}"
SUGGESTIONS_FILE="${SUGGESTIONS_FILE:-.ralph/suggested_improvements.md}"
PROGRESS_FILE="${PROGRESS_FILE:-.ralph/progress.md}"
ALLOW_CREATE_SUGGESTIONS="${ALLOW_CREATE_SUGGESTIONS:-false}"
ENFORCE_BRANCH="${ENFORCE_BRANCH:-false}"

usage() {
  cat >&2 <<EOF
Usage: scripts/check_prd.sh
Env:
  PRD_FILE: path to tasks.json (default .ralph/tasks.json)
  SUGGESTIONS_FILE: path to suggested_improvements.md (default .ralph/suggested_improvements.md)
  PROGRESS_FILE: path to progress.md (default .ralph/progress.md)
  ALLOW_CREATE_SUGGESTIONS=true|false (default false)
  ENFORCE_BRANCH=true|false (default false; when true, branchName must match current git branch)
EOF
}

if [[ "$#" -gt 0 ]]; then
  usage
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[check_prd] jq is required" >&2
  exit 1
fi

if [[ ! -f "$PRD_FILE" ]]; then
  echo "[check_prd] tasks file not found at $PRD_FILE" >&2
  exit 1
fi

if [[ ! -f "$SUGGESTIONS_FILE" ]]; then
  if [[ "$ALLOW_CREATE_SUGGESTIONS" == "true" ]]; then
    mkdir -p "$(dirname "$SUGGESTIONS_FILE")"
    echo "# Suggested Improvements" > "$SUGGESTIONS_FILE"
    echo "Created $SUGGESTIONS_FILE" >&2
  else
    echo "[check_prd] Suggestions file not found at $SUGGESTIONS_FILE (set ALLOW_CREATE_SUGGESTIONS=true to create)" >&2
    exit 1
  fi
fi

# Validate basic shape
if ! jq -e '.project and .branchName and (.tasks | type == "array")' "$PRD_FILE" >/dev/null; then
  echo "[check_prd] Missing project, branchName, or tasks array" >&2
  exit 1
fi

if [[ "$ENFORCE_BRANCH" == "true" ]] && command -v git >/dev/null 2>&1; then
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  prd_branch=$(jq -r '.branchName' "$PRD_FILE" 2>/dev/null || true)
  if [[ -n "$current_branch" && -n "$prd_branch" && "$current_branch" != "$prd_branch" ]]; then
    echo "[check_prd] branchName ($prd_branch) does not match current git branch ($current_branch)" >&2
    exit 1
  fi
fi

missing_required=$(jq -r '
  .tasks[] | select(
    (.id | not) or (.title | not) or (.description | not) or (.acceptanceCriteria | not) or (.passes | type != "boolean")
  ) | .id // "<missing-id>"' "$PRD_FILE")

if [[ -n "$missing_required" ]]; then
  echo "[check_prd] Tasks missing required fields (id/title/description/acceptanceCriteria/passes):" >&2
  echo "$missing_required" >&2
  exit 1
fi

missing_boilerplate=$(jq -r '
  .tasks[] | select(
    ([.acceptanceCriteria[]?] | index("Typecheck passes")) | not
  ) | .id' "$PRD_FILE")

if [[ -n "$missing_boilerplate" ]]; then
  echo "[check_prd] Tasks missing acceptance criterion: Typecheck passes" >&2
  echo "$missing_boilerplate" >&2
  exit 1
fi

echo "[check_prd] OK: $PRD_FILE"
