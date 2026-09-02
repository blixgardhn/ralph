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

# Boilerplate ACs (typecheck / tests) are advisory, not required. The PRD
# skill decides per task whether they apply (docs-only, config-only, and
# scaffold tasks legitimately omit them; see prompt.md §Skipped verifications
# and skills/prd/SKILL.md). check_prd.sh must not overrule that decision.
#
# We accept any AC mentioning "typecheck" (case-insensitive) — this covers
# "Typecheck passes", "Scoped typecheck passes", "Solution typecheck passes",
# etc. — and only WARN when a task has none. Same for tests.

missing_typecheck=$(jq -r '
  .tasks[] | select(
    ([.acceptanceCriteria[]?] | map(ascii_downcase) | map(test("typecheck")) | any) | not
  ) | .id' "$PRD_FILE")

if [[ -n "$missing_typecheck" ]]; then
  echo "[check_prd] WARN: tasks without a typecheck-related AC (may be intentional for docs/config/scaffold tasks):" >&2
  echo "$missing_typecheck" >&2
fi

missing_tests_ac=$(jq -r '
  .tasks[] | select(
    ([.acceptanceCriteria[]?] | map(ascii_downcase) | map(ltrimstr(" ")) | map(rtrimstr(" ")) | map(gsub("\\s+"; " ")) | map(test("test")) | any) | not
  ) | .id' "$PRD_FILE")

if [[ -n "$missing_tests_ac" ]]; then
  echo "[check_prd] WARN: tasks without any AC mentioning tests (may be intentional for docs/config tasks):" >&2
  echo "$missing_tests_ac" >&2
fi

unknown_dep_ids=$(jq -r '
  (.tasks // []) as $tasks
  | ($tasks | map(.id) | unique) as $ids
  | $tasks[]
  | {id: .id, deps: (.dependsOn // [])}
  | select(.deps | length > 0)
  | {id, missing: (.deps | map(select($ids | index(.) | not)))}
  | select(.missing | length > 0)
  | "\(.id) -> \(.missing | join(", "))"' "$PRD_FILE")

if [[ -n "$unknown_dep_ids" ]]; then
  echo "[check_prd] dependsOn references unknown task ids:" >&2
  echo "$unknown_dep_ids" >&2
  exit 1
fi

# Check for forward dependencies: if task X dependsOn Y, Y must appear before X in the array
forward_deps=$(jq -r '
  (.tasks // []) as $tasks
  | ($tasks | to_entries | map({(.value.id): .key}) | add // {}) as $idx_map
  | $tasks[]
  | {id: .id, deps: (.dependsOn // [])}
  | select(.deps | length > 0)
  | . as $task
  | ($idx_map[$task.id] // 0) as $my_idx
  | {id: $task.id, forward: ([$task.deps[] | select(($idx_map[.] // -1) >= $my_idx)])}
  | select(.forward | length > 0)
  | "\(.id) depends on later task(s): \(.forward | join(", "))"' "$PRD_FILE")

if [[ -n "$forward_deps" ]]; then
  echo "[check_prd] Forward dependencies detected (task depends on a task that appears later in the array):" >&2
  echo "$forward_deps" >&2
  exit 1
fi

echo "[check_prd] OK: $PRD_FILE"
