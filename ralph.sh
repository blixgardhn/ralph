#!/bin/bash
# Ralph Wiggum - Lean AI loop
# Usage: ./ralph.sh [--tool opencode|amp|claude] [max_iterations]
# Orchestrates short agent runs driven by prompt.md and prd.json, archiving old runs when the PRD changes.

set -euo pipefail

TOOL="opencode"
MAX_ITERATIONS=30
RALPH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # location of this script and its dependencies
TARGET_REPO_ROOT="" # target repo root where code will be generated

TARGET_REPO_ARG=""

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --tool)
        TOOL="$2"
        shift 2
        ;;
      --tool=*)
        TOOL="${1#*=}"
        shift
        ;;
      --target-repo)
        TARGET_REPO="$2"
        TARGET_REPO_ARG="$2"
        shift 2
        ;;
      --target-repo=*)
        TARGET_REPO="${1#*=}"
        TARGET_REPO_ARG="${1#*=}"
        shift
        ;;
      *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          MAX_ITERATIONS="$1"
        fi
        shift
        ;;
    esac
  done
}

# shellcheck source=./prd_utils.sh
source "$RALPH_ROOT/prd_utils.sh"

validate_tool() {
  if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "opencode" ]]; then
    echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'opencode'."
    exit 1
  fi
}

set_paths() {
  PROMPT_FILE="$RALPH_ROOT/prompt.md"

  local target_repo_input
  if [ -n "$TARGET_REPO_ARG" ]; then
    target_repo_input="$TARGET_REPO_ARG"
  elif [ -n "${TARGET_REPO:-}" ]; then
    target_repo_input="$TARGET_REPO"
  elif [ -n "${target_repo:-}" ]; then
    target_repo_input="$target_repo"
  else
    target_repo_input="$PWD"
  fi

  if [ -z "$target_repo_input" ]; then
    echo "TARGET_REPO is empty; specify --target-repo or set TARGET_REPO." >&2
    exit 1
  fi

  if ! TARGET_REPO="$(cd "$target_repo_input" 2>/dev/null && pwd)"; then
    echo "TARGET_REPO path is invalid: $target_repo_input" >&2
    exit 1
  fi

  if [ "$TARGET_REPO" = "$RALPH_ROOT" ]; then
    echo "TARGET_REPO must not be the Ralph root; point to the target repo containing .ralph." >&2
    exit 1
  fi

  TARGET_REPO_ROOT="$TARGET_REPO"

  configure_prd_paths "$TARGET_REPO_ROOT"
}

require_prompt() {
  if [ ! -f "$PROMPT_FILE" ]; then
    echo "Missing prompt file at $PROMPT_FILE"
    exit 1
  fi
}

enforce_feature_branch() {
  if ! command -v git >/dev/null 2>&1; then
    echo "[Ralph] Branch enforcement failed: git not installed." >&2
    exit 1
  fi

  if [ ! -d "$TARGET_REPO_ROOT/.git" ]; then
    echo "[Ralph] Branch enforcement failed: $TARGET_REPO_ROOT is not a git repo." >&2
    exit 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "[Ralph] Branch enforcement failed: jq not installed to read branchName from PRD." >&2
    exit 1
  fi

  local prd_branch
  prd_branch=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || true)

  if [ -z "$prd_branch" ]; then
    echo "[Ralph] PRD missing branchName; set a feature branch (e.g., ralph/<story-id>)." >&2
    exit 1
  fi

  if [ "$prd_branch" = "main" ] || [ "$prd_branch" = "master" ]; then
    echo "[Ralph] PRD branchName cannot be main/master; use a dedicated feature branch." >&2
    exit 1
  fi

  local current_branch
  current_branch=$(cd "$TARGET_REPO_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

  if [ "$current_branch" = "$prd_branch" ]; then
    return 0
  fi

  if git -C "$TARGET_REPO_ROOT" switch "$prd_branch" >/dev/null 2>&1; then
    echo "[Ralph] Switched to branch '$prd_branch' to match PRD." >&2
    return 0
  fi

  if git -C "$TARGET_REPO_ROOT" switch -c "$prd_branch" >/dev/null 2>&1; then
    echo "[Ralph] Created and switched to branch '$prd_branch' from current HEAD." >&2
    return 0
  fi

  echo "[Ralph] Could not switch to or create branch '$prd_branch'." >&2
  echo "Try manually: git -C \"$TARGET_REPO_ROOT\" switch '$prd_branch' || git -C \"$TARGET_REPO_ROOT\" switch -c '$prd_branch'" >&2
  exit 1
}

announce_story_selection() {
  local iteration="$1"

  if ! command -v jq >/dev/null 2>&1; then
    echo "[Ralph] Story selection skipped (jq not installed)." >&2
    return 0
  fi

  if [ ! -f "$PRD_FILE" ]; then
    echo "[Ralph] Story selection skipped (missing PRD at $PRD_FILE)." >&2
    return 0
  fi

  local story_json
  story_json=$(jq '(.userStories // []) | map(select(.passes != true)) | sort_by((.priority // 2147483647), .id) | .[0]' "$PRD_FILE" 2>/dev/null || true)

  if [ -z "$story_json" ] || [ "$story_json" = "null" ]; then
    echo "[Ralph] No pending stories to pick." >&2
    return 0
  fi

  local story_id story_title story_description
  story_id=$(echo "$story_json" | jq -r '.id // "<no id>"')
  story_title=$(echo "$story_json" | jq -r '.title // "<no title>"')
  story_description=$(echo "$story_json" | jq -r '.description // "<no description>"')

  local selection_block
  selection_block=$(cat <<EOF
>>> Story Selection (iteration $iteration)
ID: $story_id
Title: $story_title
Description: $story_description
EOF
)

  echo "$selection_block"

  if [ -n "$PROGRESS_FILE" ]; then
    {
      echo "## $(date --iso-8601=seconds) - Story selection (iteration $iteration)"
      echo "- ID: $story_id"
      echo "- Title: $story_title"
      echo "- Description: $story_description"
      echo "---"
    } >> "$PROGRESS_FILE"
  fi

  return 0
}

run_iteration() {
  local iteration="$1"

  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $iteration of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  announce_story_selection "$iteration"

  local OUTPUT
  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cat "$PROMPT_FILE" | amp --dangerously-allow-all 2>&1 | tee >(cat >&2)) || true
  elif [[ "$TOOL" == "claude" ]]; then
    OUTPUT=$(claude --dangerously-skip-permissions --print < "$PROMPT_FILE" 2>&1 | tee >(cat >&2)) || true
  else
    PROMPT_TEXT="$(cat "$PROMPT_FILE")"
    OUTPUT=$(opencode run "$PROMPT_TEXT" 2>&1 | tee >(cat >&2)) || true
  fi

  if command -v jq >/dev/null 2>&1 && [ -f "$PRD_FILE" ]; then
    REMAINING=$(jq '[.userStories[] | select(.passes != true)] | length' "$PRD_FILE" 2>/dev/null || echo 0)
    if [ "$REMAINING" -eq 0 ]; then
      echo "All stories marked done; rerun full test suite before finish." >&2
    fi
  fi

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks at iteration $iteration."
    exit 0
  fi

  if echo "$OUTPUT" | grep -q "<promise>STOP</promise>"; then
    echo ""
    echo "Ralph requested stop at iteration $iteration."
    exit 0
  fi

  echo "Iteration $iteration finished; continuing..."
}

run_iterations() {
  echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"
  for i in $(seq 1 "$MAX_ITERATIONS"); do
    run_iteration "$i"
  done

  echo "Reached max iterations ($MAX_ITERATIONS) without completion."
  exit 1
}

main() {
  parse_args "$@"
  validate_tool
  set_paths
  require_prd_file
  require_prompt
  enforce_feature_branch
  archive_prd_if_changed
  init_progress_file
  validate_prd
  run_iterations
}

main "$@"
