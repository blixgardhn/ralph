#!/bin/bash
# Ralph Wiggum - Lean AI loop
# Usage: ./ralph.sh [--tool opencode|amp|claude] [max_iterations]
# Orchestrates short agent runs driven by prompt.md and prd.json, archiving old runs when the PRD changes.

set -euo pipefail

TOOL="opencode"
MAX_ITERATIONS=20
PRD_HASH=""
LAST_PRD_HASH=""

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
      *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          MAX_ITERATIONS="$1"
        fi
        shift
        ;;
    esac
  done
}

validate_tool() {
  if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "opencode" ]]; then
    echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'opencode'."
    exit 1
  fi
}

set_paths() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROMPT_FILE="$SCRIPT_DIR/prompt.md"

  DEST_REPO="${DEST_REPO:-$PWD}"
  METADATA_DIR="$DEST_REPO/.ralph"
  mkdir -p "$METADATA_DIR"

  PRD_FILE="$METADATA_DIR/prd.json"
  PROGRESS_FILE="$METADATA_DIR/progress.md"
  ARCHIVE_DIR="$METADATA_DIR/archive"
  LAST_PRD_HASH_FILE="$METADATA_DIR/.last-prd-hash"
}

require_prompt() {
  if [ ! -f "$PROMPT_FILE" ]; then
    echo "Missing prompt file at $PROMPT_FILE"
    exit 1
  fi
}

archive_prd_if_changed() {
  if [ ! -f "$PRD_FILE" ]; then
    return
  fi

  PRD_HASH=$(sha1sum "$PRD_FILE" | awk '{print $1}')
  [ -f "$LAST_PRD_HASH_FILE" ] && LAST_PRD_HASH=$(cat "$LAST_PRD_HASH_FILE" || true)

  if [ -n "$LAST_PRD_HASH" ] && [ "$PRD_HASH" != "$LAST_PRD_HASH" ]; then
    DATE=$(date +%Y-%m-%d)
    NAME="prd"
    if command -v jq >/dev/null 2>&1; then
      NAME=$(jq -r '.branchName // .project // empty' "$PRD_FILE")
      [ -z "$NAME" ] && NAME="prd"
    fi
    NAME_SLUG=$(echo "$NAME" | tr '[:space:]' '-' | tr -cs '[:alnum:]._-' '-')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$NAME"
    mkdir -p "$ARCHIVE_FOLDER"
    cp "$PRD_FILE" "$ARCHIVE_FOLDER/prd-$NAME_SLUG.json"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/progress.md"
    {
      echo "## Codebase Patterns"
      echo ""
      echo "# Ralph Progress Log"
      echo "Started: $(date)"
      echo "---"
    } > "$PROGRESS_FILE"
  fi

  echo "$PRD_HASH" > "$LAST_PRD_HASH_FILE"
}

init_progress_file() {
  if [ -f "$PROGRESS_FILE" ]; then
    return
  fi

  {
    echo "## Codebase Patterns"
    echo ""
    echo "# Ralph Progress Log"
    echo "Started: $(date)"
    echo "---"
  } > "$PROGRESS_FILE"
}

validate_prd() {
  if ! command -v jq >/dev/null 2>&1; then
    return
  fi

  if [ ! -f "$PRD_FILE" ]; then
    echo "Missing PRD file at $PRD_FILE" >&2
    exit 1
  fi

  STORY_COUNT=$(jq '.userStories | length' "$PRD_FILE" 2>/dev/null || echo 0)
  if [ "$STORY_COUNT" -eq 0 ]; then
    echo "PRD has no userStories; add stories before running Ralph." >&2
    exit 1
  fi

  MISSING_FIELDS=$(jq -r '.userStories[] | select((.id? | type != "string") or (.title? | type != "string") or (.passes? | type != "boolean")) | .id // "<no id>"' "$PRD_FILE" 2>/dev/null || true)
  if [ -n "$MISSING_FIELDS" ]; then
    echo "PRD has stories missing required fields (id/title/passes). Offending IDs: $MISSING_FIELDS" >&2
    exit 1
  fi
}

run_iteration() {
  local iteration="$1"

  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $iteration of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  local OUTPUT
  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cat "$PROMPT_FILE" | amp --dangerously-allow-all 2>&1 | tee >(cat >&2)) || true
  elif [[ "$TOOL" == "claude" ]]; then
    OUTPUT=$(claude --dangerously-skip-permissions --print < "$PROMPT_FILE" 2>&1 | tee >(cat >&2)) || true
  else
    PROMPT_TEXT="$(cat "$PROMPT_FILE")"
    OUTPUT$(opencode run "$PROMPT_TEXT" 2>&1 | tee >(cat >&2)) || true
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
  require_prompt
  archive_prd_if_changed
  init_progress_file
  validate_prd
  run_iterations
}

main "$@"
