#!/usr/bin/env bash
set -euo pipefail

PRD_FILE="${PRD_FILE:-.ralph/prd.json}"

usage() {
  echo "Usage: PRD_FILE=/path/to/prd.json scripts/check_prd.sh" >&2
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
  echo "[check_prd] PRD file not found at $PRD_FILE" >&2
  exit 1
fi

# Validate basic shape
if ! jq -e '.project and .branchName and (.userStories | type == "array")' "$PRD_FILE" >/dev/null; then
  echo "[check_prd] Missing project, branchName, or userStories array" >&2
  exit 1
fi

missing_required=$(jq -r '

if [[ -n "$missing_required" ]]; then
  echo "[check_prd] Stories missing required fields (id/title/description/acceptanceCriteria/passes):" >&2
  echo "$missing_required" >&2
  exit 1
fi

missing_boilerplate=$(jq -r '

if [[ -n "$missing_boilerplate" ]]; then
  echo "[check_prd] Stories missing acceptance criterion: Typecheck passes" >&2
  echo "$missing_boilerplate" >&2
  exit 1
fi

echo "[check_prd] OK: $PRD_FILE"
