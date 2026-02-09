#!/bin/bash

# PRD and progress handling utilities for Ralph.

# Initialize globals to avoid unbound variable errors when sourced under `set -u`.
METADATA_DIR=""
PRD_FILE=""
PROGRESS_FILE=""
SUGGESTIONS_FILE=""
ARCHIVE_DIR=""
LAST_PRD_HASH_FILE=""

configure_prd_paths() {
  local target_root="$1"

  METADATA_DIR="$target_root/.ralph"
  mkdir -p "$METADATA_DIR"

  PRD_FILE="$METADATA_DIR/prd.json"
  PROGRESS_FILE="$METADATA_DIR/progress.md"

  SUGGESTIONS_FILE="$METADATA_DIR/suggested_improvements.md"
  ARCHIVE_DIR="$METADATA_DIR/archive"
  LAST_PRD_HASH_FILE="$METADATA_DIR/.last-prd-hash"
}

require_prd_file() {
  if [ ! -f "$PRD_FILE" ]; then
    echo "Missing PRD file; expected at $PRD_FILE" >&2
    exit 1
  fi
}

archive_prd_if_changed() {
  if [ ! -f "$PRD_FILE" ]; then
    return
  fi

  local prd_hash=""
  local last_prd_hash=""
  local unfinished_count=""

  prd_hash=$(sha1sum "$PRD_FILE" | awk '{print $1}')
  [ -f "$LAST_PRD_HASH_FILE" ] && last_prd_hash=$(cat "$LAST_PRD_HASH_FILE" || true)

  if command -v jq >/dev/null 2>&1; then
    unfinished_count=$(jq '[.userStories[] | select(.passes != true)] | length' "$PRD_FILE" 2>/dev/null || echo "")
  fi

  if [ -n "$unfinished_count" ] && [ "$unfinished_count" -gt 0 ]; then
    echo "[Ralph] Skipping PRD archive: $unfinished_count unfinished stories remain." >&2
    echo "$prd_hash" > "$LAST_PRD_HASH_FILE"
    return
  fi

  if [ -n "$last_prd_hash" ] && [ "$prd_hash" != "$last_prd_hash" ]; then
    local date name name_slug archive_folder

    date=$(date +%Y-%m-%d)
    name="prd"
    if command -v jq >/dev/null 2>&1; then
      name=$(jq -r '.branchName // .project // empty' "$PRD_FILE")
      [ -z "$name" ] && name="prd"
    fi
    name_slug=$(echo "$name" | tr '[:space:]' '-' | tr -cs '[:alnum:]._-' '-')
    archive_folder="$ARCHIVE_DIR/$date-$name"
    mkdir -p "$archive_folder"
    cp "$PRD_FILE" "$archive_folder/prd-$name_slug.json"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$archive_folder/progress.md"
    # Do not archive suggestions when they live outside the target repo; they stay in the runner.
    {
      echo "## Codebase Patterns"
      echo ""
      echo "# Ralph Progress Log"
      echo "Started: $(date)"
      echo "---"
    } > "$PROGRESS_FILE"
  fi

  echo "$prd_hash" > "$LAST_PRD_HASH_FILE"
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

init_suggestions_file() {
  if [ -z "$SUGGESTIONS_FILE" ]; then
    return
  fi

  if [ -f "$SUGGESTIONS_FILE" ]; then
    return
  fi

  {
    echo "# Suggested Improvements"
    echo "Notes captured after each Ralph iteration; implement separately."
    echo "---"
  } > "$SUGGESTIONS_FILE"
}

append_suggestion_entry() {
  local iteration="$1"
  local outcome="$2"
  local detail="$3"

  if [ -z "$SUGGESTIONS_FILE" ]; then
    return
  fi

  {
    echo "## $(date --iso-8601=seconds) - Iteration $iteration ($outcome)"
    echo "- $detail"
    echo "---"
  } >> "$SUGGESTIONS_FILE"
}

# Extract actionable suggestions from an iteration output and append only if present.
# Heuristics look for lines containing "suggestion:" or "improvement:" (case-insensitive)
# and capture bullet-style or sentence entries.
record_suggestions() {
  local iteration="$1"
  local outcome="$2"
  local output="$3"

  if [ -z "$output" ]; then
    return
  fi

  # Collect unique suggestion lines.
  local suggestions
  suggestions=$(printf '%s\n' "$output" | grep -i -E 'suggestion:|improvement:' | sed 's/^[-*]\s*//g' | sed 's/^\s*//g' | sort -u)

  if [ -z "$suggestions" ]; then
    return
  fi

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    append_suggestion_entry "$iteration" "$outcome" "$line"
  done <<< "$suggestions"
}

validate_prd() {
  if ! command -v jq >/dev/null 2>&1; then
    return
  fi

  local story_count missing_fields

  story_count=$(jq '.userStories | length' "$PRD_FILE" 2>/dev/null || echo 0)
  if [ "$story_count" -eq 0 ]; then
    echo "PRD has no userStories; add stories before running Ralph." >&2
    exit 1
  fi

  missing_fields=$(jq -r '.userStories[] | select((.id? | type != "string") or (.title? | type != "string") or (.passes? | type != "boolean")) | .id // "<no id>"' "$PRD_FILE" 2>/dev/null || true)
  if [ -n "$missing_fields" ]; then
    echo "PRD has stories missing required fields (id/title/passes). Offending IDs: $missing_fields" >&2
    exit 1
  fi
}
