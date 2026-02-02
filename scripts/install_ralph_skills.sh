#!/usr/bin/env bash

set -euo pipefail

# Install the Ralph skills (prd, ralph_setup) into OpenCode, Amp, or Claude skills directories.
# Usage:
#   ./install_ralph_skills.sh [target_dir]
#
# If target_dir is omitted, installs to:
#   - OpenCode: $HOME/.config/opencode/skills (or $OPENCODE_SKILLS_DIR)
#   - Amp:      $HOME/.config/amp/skills
#   - Claude:   $HOME/.claude/skills

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo "Error: skills directory not found at $SKILLS_SRC" >&2
  exit 1
fi

DEFAULT_TARGET="$HOME/.config/opencode/skills"
TARGET_DIR="${1:-${OPENCODE_SKILLS_DIR:-$DEFAULT_TARGET}}"
AMP_TARGET="$HOME/.config/amp/skills"
CLAUDE_TARGET="$HOME/.claude/skills"

install_set() {
  local dest="$1"
  mkdir -p "$dest"
  for SKILL_NAME in prd ralph_setup; do
    local SRC_PATH="$SKILLS_SRC/$SKILL_NAME"
    local DEST_PATH="$dest/$SKILL_NAME"
    if [[ ! -d "$SRC_PATH" ]]; then
      echo "Warning: missing skill source $SRC_PATH; skipping" >&2
      continue
    fi
    rm -rf "$DEST_PATH"
    mkdir -p "$DEST_PATH"
    cp -R "$SRC_PATH/." "$DEST_PATH/"
    echo "Installed $SKILL_NAME to $DEST_PATH"
  done
}

install_set "$TARGET_DIR"
echo "Done. OpenCode skills installed in $TARGET_DIR"

if [[ -d "$AMP_TARGET" || ! -e "$AMP_TARGET" ]]; then
  install_set "$AMP_TARGET"
  echo "Amp skills installed in $AMP_TARGET"
fi

if [[ -d "$CLAUDE_TARGET" || ! -e "$CLAUDE_TARGET" ]]; then
  install_set "$CLAUDE_TARGET"
  echo "Claude skills installed in $CLAUDE_TARGET"
fi
