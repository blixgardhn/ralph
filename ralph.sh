#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool opencode|amp|claude] [max_iterations]

set -e

# Parse arguments
TOOL="opencode"  # Default to opencode for backwards compatibility
MAX_ITERATIONS=10
FORCE_MAIN=0
ALLOW_DIRTY=0
CLEAR_FAILED=0

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
    --force-main)
      FORCE_MAIN=1
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --clear-failed)
      CLEAR_FAILED=1
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "opencode" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'opencode'."
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.md"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
LAST_PRD_HASH_FILE="$SCRIPT_DIR/.last-prd-hash"
FAILED_FILE="$SCRIPT_DIR/.ralph-test-failed"
LOG_FILE="$SCRIPT_DIR/ralph.log"

# Archive previous run if branch changed or PRD content changed
PRD_HASH=""
LAST_PRD_HASH=""
PRD_CHANGED=0
CURRENT_BRANCH=""
LAST_BRANCH=""

if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  PRD_HASH=$(sha1sum "$PRD_FILE" | awk '{print $1}')
fi

[ -f "$LAST_BRANCH_FILE" ] && LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
[ -f "$LAST_PRD_HASH_FILE" ] && LAST_PRD_HASH=$(cat "$LAST_PRD_HASH_FILE" 2>/dev/null || echo "")

if [ -n "$PRD_HASH" ] && [ -n "$LAST_PRD_HASH" ] && [ "$PRD_HASH" != "$LAST_PRD_HASH" ]; then
  PRD_CHANGED=1
fi

touch "$LOG_FILE"
log_line() {
  local ts
  ts=$(date -Is)
  echo "[$ts] $1" | tee -a "$LOG_FILE"
}

ARCHIVE_REASON=""
if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
  ARCHIVE_REASON="branch change"
fi
if [ $PRD_CHANGED -eq 1 ]; then
  if [ -n "$ARCHIVE_REASON" ]; then
    ARCHIVE_REASON="$ARCHIVE_REASON + new PRD content"
  else
    ARCHIVE_REASON="new PRD content"
  fi
fi

if [ -n "$ARCHIVE_REASON" ]; then
  DATE=$(date +%Y-%m-%d)
  FOLDER_NAME=$(echo "${LAST_BRANCH:-$CURRENT_BRANCH:-unknown-prd}" | sed 's|^ralph/||')
  ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

  log_line "Archiving previous run due to: $ARCHIVE_REASON -> $ARCHIVE_FOLDER"
  mkdir -p "$ARCHIVE_FOLDER"
  [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
  [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
  log_line "Archive complete: $ARCHIVE_FOLDER/prd.json and progress.md"

  {
    echo "## Codebase Patterns"
    echo "- Run all dependency installation, tooling, testing, builds, and database seeding inside containers (Docker/Podman/Compose); keep the host free of project toolchains"
    echo ""
    echo "# Ralph Progress Log"
    echo "Started: $(date)"
    echo "---"
  } > "$PROGRESS_FILE"
fi

# Track current branch and PRD hash
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
  if [ -n "$PRD_HASH" ]; then
    echo "$PRD_HASH" > "$LAST_PRD_HASH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  {
    echo "## Codebase Patterns"
    echo "- Run all dependency installation, tooling, testing, builds, and database seeding inside containers (Docker/Podman/Compose); keep the host free of project toolchains"
    echo ""
    echo "# Ralph Progress Log"
    echo "Started: $(date)"
    echo "---"
  } > "$PROGRESS_FILE"
fi

GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ "$GIT_BRANCH" =~ ^(main|master)$ && $FORCE_MAIN -ne 1 ]]; then
  log_line "Refusing to run on $GIT_BRANCH. Use --force-main to override."
  echo "Refusing to run on $GIT_BRANCH. Use --force-main to override." >&2
  exit 1
fi

# Dirty tree guard
if [ $ALLOW_DIRTY -ne 1 ]; then
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    log_line "Working tree is dirty. Commit, stash, or rerun with --allow-dirty."
    echo "Working tree is dirty. Commit, stash, or rerun with --allow-dirty." >&2
    exit 1
  fi
fi

# Failed checks guard
if [ -f "$FAILED_FILE" ] && [ $CLEAR_FAILED -ne 1 ]; then
  log_line "Previous iteration recorded failed checks. Resolve and remove $FAILED_FILE or rerun with --clear-failed."
  echo "Previous iteration recorded failed checks. Resolve and remove $FAILED_FILE or rerun with --clear-failed." >&2
  exit 1
fi
if [ $CLEAR_FAILED -eq 1 ]; then
  rm -f "$FAILED_FILE"
  log_line "Cleared failed-check marker ($FAILED_FILE)"
fi

# Ensure branch exists/checked out if PRD specifies one
if [ -n "$CURRENT_BRANCH" ]; then
  if git show-ref --verify --quiet "refs/heads/$CURRENT_BRANCH"; then
    git checkout "$CURRENT_BRANCH" >/dev/null 2>&1 || git checkout "$CURRENT_BRANCH"
  else
    echo "Creating branch $CURRENT_BRANCH from current HEAD"
    git checkout -b "$CURRENT_BRANCH"
  fi
fi

log_line "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS - Branch: ${CURRENT_BRANCH:-$GIT_BRANCH}"
echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS - Branch: ${CURRENT_BRANCH:-$GIT_BRANCH}"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  log_line "Iteration $i/$MAX_ITERATIONS start"
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  # Run the selected tool with the ralph prompt
  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true

  elif [[ "$TOOL" == "claude" ]]; then
    OUTPUT=$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/prompt.md" 2>&1 | tee /dev/stderr) || true

  else
    # OpenCode: run with prompt passed as a single argument
    PROMPT_TEXT="$(cat "$SCRIPT_DIR/prompt.md")"
    OUTPUT=$(opencode run "$PROMPT_TEXT" 2>&1 | tee /dev/stderr) || true

    # Optional: if you want structured output for more robust parsing:
    # OUTPUT=$(opencode run --format json "$PROMPT_TEXT" 2>&1 | tee /dev/stderr) || true
  fi

  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    log_line "COMPLETE signal received at iteration $i"
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  log_line "Iteration $i complete. Continuing..."
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

log_line "Reached max iterations ($MAX_ITERATIONS) without completion"
echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
