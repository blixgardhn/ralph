#!/usr/bin/env bash

set -euo pipefail

# Install the Ralph skills (prd, ralph_prd, ralph_setup) into an OpenCode skills directory.
# Usage: ./install_ralph_skills.sh [target_dir]

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo "Error: skills directory not found at $SKILLS_SRC" >&2
  exit 1
fi

DEFAULT_TARGET="$HOME/.config/opencode/skills"
TARGET_DIR="${1:-${OPENCODE_SKILLS_DIR:-$DEFAULT_TARGET}}"

mkdir -p "$TARGET_DIR"

for SKILL_NAME in prd ralph_prd ralph_setup; do
  SRC_PATH="$SKILLS_SRC/$SKILL_NAME"
  DEST_PATH="$TARGET_DIR/$SKILL_NAME"

  if [[ ! -d "$SRC_PATH" ]]; then
    echo "Warning: missing skill source $SRC_PATH; skipping" >&2
    continue
  fi

  rm -rf "$DEST_PATH"
  mkdir -p "$DEST_PATH"
  cp -R "$SRC_PATH/." "$DEST_PATH/"
  echo "Installed $SKILL_NAME to $DEST_PATH"
done

echo "Done. OpenCode skills installed in $TARGET_DIR"
