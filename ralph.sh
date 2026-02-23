#!/bin/bash
# Ralph Wiggum - Lean AI loop
# Usage: ./ralph.sh [--tool opencode|amp|claude] [max_iterations]
# Orchestrates short agent runs driven by prompt.md and tasks.json, archiving old runs when the PRD changes.

set -euo pipefail

TOOL="opencode"
MAX_ITERATIONS=30
OPENCODE_MODEL="${OPENCODE_MODEL:-github-copilot/gpt-5.1-codex-max}"
RALPH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # location of this script and its dependencies
TARGET_REPO_ROOT="" # target repo root where code will be generated
RUNNER_AGENTS_FILE="$RALPH_ROOT/AGENTS.md"

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
# shellcheck source=./timer_utils.sh
source "$RALPH_ROOT/timer_utils.sh"

validate_tool() {
  if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "opencode" ]]; then
    echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'opencode'."
    exit 1
  fi
}

set_paths() {
  local invocation_pwd
  invocation_pwd="$PWD"

  PROMPT_FILE="$RALPH_ROOT/prompt.md"

  local target_repo_input
  if [ -n "$TARGET_REPO_ARG" ]; then
    target_repo_input="$TARGET_REPO_ARG"
  elif [ -n "${TARGET_REPO:-}" ]; then
    target_repo_input="$TARGET_REPO"
  elif [ -n "${target_repo:-}" ]; then
    target_repo_input="$target_repo"
  else
    target_repo_input="$invocation_pwd"
  fi

  if [ -z "$target_repo_input" ]; then
    echo "TARGET_REPO is empty; specify --target-repo or set TARGET_REPO." >&2
    exit 1
  fi

  if ! TARGET_REPO="$(cd "$target_repo_input" 2>/dev/null && pwd)"; then
    echo "TARGET_REPO path is invalid: $target_repo_input" >&2
    exit 1
  fi

  case "$TARGET_REPO" in
    "$RALPH_ROOT"|"$RALPH_ROOT"/*)
      echo "TARGET_REPO must not be the Ralph runner directory; point to the target repo containing .ralph." >&2
      echo "Resolved target: $TARGET_REPO" >&2
      exit 1
      ;;
  esac

  TARGET_REPO_ROOT="$TARGET_REPO"

  configure_prd_paths "$TARGET_REPO_ROOT"
}

require_agents_file() {
  if [ ! -f "$RUNNER_AGENTS_FILE" ]; then
    echo "Missing AGENTS file at $RUNNER_AGENTS_FILE" >&2
    exit 1
  fi
}

require_prompt_file() {
  if [ ! -f "$PROMPT_FILE" ]; then
    echo "Missing prompt file at $PROMPT_FILE" >&2
    exit 1
  fi
}

hash_and_size() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "absent"
    return
  fi
  local hash size
  hash=$(sha1sum "$path" | awk '{print $1}')
  size=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null || echo "?")
  printf "%s/%s" "${hash:0:12}" "$size"
}

fail_if_target_instructions_present() {
  local target_agents="$TARGET_REPO_ROOT/AGENTS.md"
  local target_prompt="$TARGET_REPO_ROOT/ralph/prompt.md"

  if [ -f "$target_agents" ]; then
    echo "[Ralph] Error: target repo contains AGENTS.md ($target_agents) but runner instructions at $RUNNER_AGENTS_FILE must be used. Remove or rename the target copy." >&2
    exit 1
  fi

  if [ -f "$target_prompt" ]; then
    echo "[Ralph] Error: target repo contains ralph/prompt.md ($target_prompt) but runner prompt at $PROMPT_FILE must be used. Remove or rename the target copy." >&2
    exit 1
  fi
}

log_instruction_fingerprints() {
  local agents_sig prompt_sig
  agents_sig=$(hash_and_size "$RUNNER_AGENTS_FILE")
  prompt_sig=$(hash_and_size "$PROMPT_FILE")
  echo "[Ralph] Using runner instructions: AGENTS=$agents_sig PROMPT=$prompt_sig" >&2
}

log_context_resources() {
  local rules_dotnet rules_python process_contract specs_count specs_hash specs_files
  rules_dotnet=$(hash_and_size "$RALPH_ROOT/code_generation_rules/RULES-dotnet.md")
  rules_python=$(hash_and_size "$RALPH_ROOT/code_generation_rules/RULES-python.md")
  process_contract=$(hash_and_size "$RALPH_ROOT/process_contract")

  specs_count="0"
  specs_hash="absent"
  specs_files=""
  if [ -d "$RALPH_ROOT/specs" ]; then
    specs_count=$(find "$RALPH_ROOT/specs" -maxdepth 1 -type f | wc -l | awk '{print $1}')
    if [ "$specs_count" -gt 0 ]; then
      specs_hash=$(find "$RALPH_ROOT/specs" -maxdepth 1 -type f -exec sha1sum {} + | sha1sum | awk '{print $1}')
      specs_files=$(cd "$RALPH_ROOT/specs" && find . -maxdepth 1 -type f -print | sed 's#^./##' | sort | head -n 10 | tr '\n' ',' | sed 's/,$//')
    fi
  fi

  echo "[Ralph] Context resources (runner): rules(dotnet)=$rules_dotnet rules(python)=$rules_python process_contract=$process_contract specs=count:$specs_count hash:${specs_hash:0:12} files:$specs_files" >&2
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

warn_if_target_instructions_present() {
  local target_agents="$TARGET_REPO_ROOT/AGENTS.md"
  local target_prompt="$TARGET_REPO_ROOT/ralph/prompt.md"
  local warned=false

  if [ -f "$target_agents" ]; then
    echo "[Ralph] Warning: found AGENTS.md in target repo ($target_agents) but runner instructions at $RALPH_ROOT/AGENTS.md will be used." >&2
    warned=true
  fi

  if [ -f "$target_prompt" ]; then
    echo "[Ralph] Warning: found ralph/prompt.md in target repo ($target_prompt) but runner prompt at $RALPH_ROOT/prompt.md will be used." >&2
    warned=true
  fi

  if [ "$warned" = true ]; then
    echo "[Ralph] If you intend to use target copies, run Ralph from the runner directory or adjust invocation." >&2
  fi
}

announce_story_selection() {
  local iteration="$1"

  if ! command -v jq >/dev/null 2>&1; then
    echo "[Ralph] Task selection skipped (jq not installed)." >&2
    return 0
  fi

  if [ ! -f "$PRD_FILE" ]; then
    echo "[Ralph] Task selection skipped (missing PRD at $PRD_FILE)." >&2
    return 0
  fi

  local story_json
  story_json=$(jq '(.tasks // []) | map(select(.passes != true)) | sort_by((.priority // 2147483647), .id) | .[0]' "$PRD_FILE" 2>/dev/null || true)

  if [ -z "$story_json" ] || [ "$story_json" = "null" ]; then
    echo "[Ralph] No pending tasks to pick." >&2
    return 0
  fi

  local story_id story_title story_description
  story_id=$(echo "$story_json" | jq -r '.id // "<no id>"')
  story_title=$(echo "$story_json" | jq -r '.title // "<no title>"')
  story_description=$(echo "$story_json" | jq -r '.description // "<no description>"')

  local selection_block
  selection_block=$(cat <<EOF
>>> Task Selection (iteration $iteration)
ID: $story_id
Title: $story_title
Description: $story_description
EOF
)

  echo "$selection_block"

  if [ -n "$PROGRESS_FILE" ]; then
    {
      echo "## $(date --iso-8601=seconds) - Task selection (iteration $iteration)"
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
  local iter_start
  iter_start=$(date +%s)

  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $iteration of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

   announce_story_selection "$iteration"

  local OUTPUT
  local merged_prompt
  merged_prompt="$(cat "$RUNNER_AGENTS_FILE"; printf '\n'; cat "$PROMPT_FILE")"
  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cd "$TARGET_REPO_ROOT" && printf "%s" "$merged_prompt" | amp --dangerously-allow-all 2>&1 | tee >(cat >&2)) || true
  elif [[ "$TOOL" == "claude" ]]; then
    OUTPUT=$(cd "$TARGET_REPO_ROOT" && printf "%s" "$merged_prompt" | claude --dangerously-skip-permissions --print 2>&1 | tee >(cat >&2)) || true
  else
    OUTPUT=$(cd "$TARGET_REPO_ROOT" && printf "%s" "$merged_prompt" | opencode run --model "$OPENCODE_MODEL" 2>&1 | tee >(cat >&2)) || true
  fi

  if command -v jq >/dev/null 2>&1 && [ -f "$PRD_FILE" ]; then
    REMAINING=$(jq '[.tasks[] | select(.passes != true)] | length' "$PRD_FILE" 2>/dev/null || echo 0)
    if [ "$REMAINING" -eq 0 ]; then
       echo "All tasks marked done; rerun full test suite before finish." >&2
    fi
  fi

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks at iteration $iteration."
    record_suggestions "$iteration" "complete" "$OUTPUT"
    local iter_end elapsed loop_elapsed
    iter_end=$(date +%s)
    elapsed=$((iter_end - iter_start))
    loop_elapsed=$((iter_end - LOOP_START_SECS))
    echo "[Ralph][timer] iteration=$iteration duration=$(format_duration "$elapsed") total_elapsed=$(format_duration "$loop_elapsed")" >&2
    exit 0
  fi

  if echo "$OUTPUT" | grep -q "<promise>STOP</promise>"; then
    echo ""
    echo "Ralph requested stop at iteration $iteration."
    record_suggestions "$iteration" "stopped" "$OUTPUT"
    local iter_end elapsed loop_elapsed
    iter_end=$(date +%s)
    elapsed=$((iter_end - iter_start))
    loop_elapsed=$((iter_end - LOOP_START_SECS))
    echo "[Ralph][timer] iteration=$iteration duration=$(format_duration "$elapsed") total_elapsed=$(format_duration "$loop_elapsed")" >&2
    exit 0
  fi

  record_suggestions "$iteration" "continued" "$OUTPUT"
  local iter_end elapsed loop_elapsed remaining_tasks completed_tasks
  iter_end=$(date +%s)
  elapsed=$((iter_end - iter_start))
  loop_elapsed=$((iter_end - LOOP_START_SECS))
  if command -v jq >/dev/null 2>&1 && [ -f "$PRD_FILE" ]; then
    remaining_tasks=$(jq '(.tasks // []) | map(select(.passes != true)) | length' "$PRD_FILE" 2>/dev/null || echo 0)
  else
    remaining_tasks=0
  fi
  completed_tasks=$(compute_completed_tasks "$TOTAL_TASKS" "$remaining_tasks")
  echo "[Ralph][timer] iteration=$iteration duration=$(format_duration "$elapsed") total_elapsed=$(format_duration "$loop_elapsed")" >&2
  render_progress "$completed_tasks" "$remaining_tasks" "$loop_elapsed"
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
  require_agents_file
  require_prompt_file
  fail_if_target_instructions_present
  log_instruction_fingerprints
  log_context_resources
  warn_if_target_instructions_present
  require_prd_file
  if [ -x "$RALPH_ROOT/scripts/check_prd.sh" ]; then
    PRD_FILE="$PRD_FILE" SUGGESTIONS_FILE="$SUGGESTIONS_FILE" PROGRESS_FILE="$PROGRESS_FILE" ALLOW_CREATE_SUGGESTIONS=true "$RALPH_ROOT/scripts/check_prd.sh"
  fi
  enforce_feature_branch
  archive_prd_if_changed
  init_progress_file
  init_suggestions_file
  validate_prd
  LOOP_START_SECS=$(date +%s)
  compute_total_tasks
  run_iterations
}

main "$@"
