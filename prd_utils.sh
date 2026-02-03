#!/bin/bash

# PRD and progress handling utilities for Ralph.

# Initialize globals to avoid unbound variable errors when sourced under `set -u`.
METADATA_DIR=""
PRD_FILE=""
PROGRESS_FILE=""
ARCHIVE_DIR=""
LAST_PRD_HASH_FILE=""

configure_prd_paths() {
  local target_root="$1"

  METADATA_DIR="$target_root/.ralph"
  mkdir -p "$METADATA_DIR"

  PRD_FILE="$METADATA_DIR/prd.json"
  PROGRESS_FILE="$METADATA_DIR/progress.md"
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

  prd_hash=$(sha1sum "$PRD_FILE" | awk '{print $1}')
  [ -f "$LAST_PRD_HASH_FILE" ] && last_prd_hash=$(cat "$LAST_PRD_HASH_FILE" || true)

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
