#!/bin/bash
# Ralph Wiggum - Lean AI loop
# Usage: ./ralph.sh [--tool opencode|amp|claude] [--opencode-model <model>] [max_iterations]
# Orchestrates short agent runs driven by prompt.md and tasks.json, archiving old runs when the PRD changes.

set -euo pipefail

TOOL="opencode"
MAX_ITERATIONS=30
OPENCODE_MODEL="${OPENCODE_MODEL:-github-copilot/gpt-5.1-codex-max}"
RALPH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # location of this script and its dependencies
export RALPH_ROOT
TARGET_REPO_ROOT="" # target repo root where code will be generated
export TARGET_REPO_ROOT
RUNNER_AGENTS_FILE="$RALPH_ROOT/ralph-specs/AGENTS.md"
RESOLVED_AGENTS_FILE=""
RESOLVED_PROMPT_FILE=""

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
      --opencode-model)
        OPENCODE_MODEL="$2"
        shift 2
        ;;
      --opencode-model=*)
        OPENCODE_MODEL="${1#*=}"
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

  PROMPT_FILE="$RALPH_ROOT/ralph-specs/prompt.md"

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
      echo "TARGET_REPO must not be the Ralph runner directory; point to a project repo containing .ralph." >&2
      echo "Resolved target: $TARGET_REPO" >&2
      exit 1
      ;;
  esac

  TARGET_REPO_ROOT="$TARGET_REPO"
  export TARGET_REPO_ROOT

  configure_prd_paths "$TARGET_REPO_ROOT"
}

require_agents_file() {
  # Soft requirement: prefer runner AGENTS, but do not stop the loop if missing.
  if [ ! -f "$RUNNER_AGENTS_FILE" ]; then
    echo "[Ralph][warn] Missing runner AGENTS at $RUNNER_AGENTS_FILE; will look for a target fallback." >&2
    return 1
  fi
  return 0
}

require_runner_specs_dir() {
  local specs_dir="$RALPH_ROOT/ralph-specs"
  if [ ! -d "$specs_dir" ]; then
    echo "[Ralph][warn] Runner specs directory missing at $specs_dir; proceeding without appended specs." >&2
    return 1
  fi
  return 0
}

collect_ralph_specs() {
  local specs_dir="$RALPH_ROOT/ralph-specs"
  if [ ! -d "$specs_dir" ]; then
    echo "[Ralph][warn] Specs directory $specs_dir not found; skipping specs append." >&2
    return
  fi

  # Deterministic ordering: limit to core instruction files and sort by relative path.
  local files
  IFS=$'\n' read -r -d '' -a files < <(printf "%s\n" \
    "$specs_dir/AGENTS.md" \
    "$specs_dir/prompt.md" \
    "$specs_dir/code_generation_rules/RULES.md" \
    "$specs_dir/code_generation_rules/RULES-dotnet.md" \
    "$specs_dir/code_generation_rules/RULES-python.md" \
    "$specs_dir/README.md" 2>/dev/null | awk 'NF' | sort -u && printf '\0') || true

  local file rel
  for file in "${files[@]}"; do
    [ -f "$file" ] || continue
    rel=${file#"$RALPH_ROOT/"}
    printf '\n### Begin %s\n' "$rel"
    cat "$file"
    printf '\n### End %s\n' "$rel"
  done
}

require_prompt_file() {
  # Soft requirement: prefer runner prompt, but do not stop the loop if missing.
  if [ ! -f "$PROMPT_FILE" ]; then
    echo "[Ralph][warn] Missing runner prompt at $PROMPT_FILE; will look for a target fallback." >&2
    return 1
  fi
  return 0
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

resolve_instruction_files() {
  local target_agents="$TARGET_REPO_ROOT/AGENTS.md"
  local target_prompt="$TARGET_REPO_ROOT/ralph/prompt.md"

  RESOLVED_AGENTS_FILE=""
  RESOLVED_PROMPT_FILE=""

  if [ -f "$RUNNER_AGENTS_FILE" ]; then
    RESOLVED_AGENTS_FILE="$RUNNER_AGENTS_FILE"
    if [ -f "$target_agents" ]; then
      echo "[Ralph][warn] Target has AGENTS at $target_agents; runner copy will be used." >&2
    fi
  elif [ -f "$target_agents" ]; then
    RESOLVED_AGENTS_FILE="$target_agents"
    echo "[Ralph][warn] Using target AGENTS fallback at $target_agents (runner copy missing)." >&2
  else
    echo "[Ralph][warn] No AGENTS.md found (runner or target); prompt will include a placeholder." >&2
  fi

  if [ -f "$PROMPT_FILE" ]; then
    RESOLVED_PROMPT_FILE="$PROMPT_FILE"
    if [ -f "$target_prompt" ]; then
      echo "[Ralph][warn] Target has ralph/prompt.md at $target_prompt; runner copy will be used." >&2
    fi
  elif [ -f "$target_prompt" ]; then
    RESOLVED_PROMPT_FILE="$target_prompt"
    echo "[Ralph][warn] Using target prompt fallback at $target_prompt (runner copy missing)." >&2
  else
    echo "[Ralph][warn] No prompt file found (runner or target); prompt will include a placeholder." >&2
  fi
}

log_instruction_fingerprints() {
  local agents_sig prompt_sig
  agents_sig=$(hash_and_size "${RESOLVED_AGENTS_FILE:-$RUNNER_AGENTS_FILE}")
  prompt_sig=$(hash_and_size "${RESOLVED_PROMPT_FILE:-$PROMPT_FILE}")
  echo "[Ralph] Using instructions: AGENTS=$agents_sig PROMPT=$prompt_sig" >&2
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

  if [ -f "$target_agents" ]; then
    echo "[Ralph][warn] Target repo has AGENTS at $target_agents." >&2
  fi

  if [ -f "$target_prompt" ]; then
    echo "[Ralph][warn] Target repo has ralph/prompt.md at $target_prompt." >&2
  fi
}

announce_story_selection() {
  local iteration="$1"

  SELECTED_TASK_ID=""
  SELECTED_TASK_TITLE=""
  BLOCKED_IDS=""
  UNKNOWN_DEP_IDS=""

  if ! command -v jq >/dev/null 2>&1; then
    echo "[Ralph] Task selection skipped (jq not installed)." >&2
    return 0
  fi

  if [ ! -f "$PRD_FILE" ]; then
    echo "[Ralph] Task selection skipped (missing PRD at $PRD_FILE)." >&2
    return 0
  fi

  local selection_json
  selection_json=$(jq -c '
    def len0(x): (x // [] | length);
    def str_len(x): (x // "" | tostring | length);
    (.tasks // [])
    | to_entries
    | map({
        __idx: .key,
        id: (.value.id // "<no id>"),
        title: (.value.title // ""),
        description: (.value.description // ""),
        passes: (.value.passes == true),
        po: (.value.poRank // 2147483647),
        deps: (.value.dependsOn // []),
        ac_count: len0(.value.acceptanceCriteria),
        sub_count: len0(.value.subtasks)
      }) as $all
    | ($all | map(.id) | unique) as $ids
    | ($all | map(.deps // []) | flatten | unique | map(select(($ids | index(.)) | not))) as $unknown
    | ($all | map(select(.passes)) | map(.id) | map({(.) : true}) | add // {}) as $done_map
    | ($all
        | map(select(.passes|not))
        | map(. + {
            deps_satisfied: ( (len0(.deps) == 0) or ((.deps | all($done_map[.] // false))) )
          })
      ) as $pending
    | ($pending | map(select(.deps_satisfied)) | sort_by([.po, .__idx, .ac_count, .sub_count, (str_len(.title)+str_len(.description)), .id])) as $unblocked
    | ($pending | map(select(.deps_satisfied|not))) as $blocked
    | {
        selected: ($unblocked[0] // null),
        blocked: $blocked,
        unknownDeps: $unknown
      }
  ' "$PRD_FILE" 2>/dev/null || true)

  if [ -z "$selection_json" ]; then
    echo "[Ralph] Task selection failed (no selection JSON)." >&2
    return 0
  fi

  SELECTED_TASK_ID=$(echo "$selection_json" | jq -r '.selected.id // ""')
  SELECTED_TASK_TITLE=$(echo "$selection_json" | jq -r '.selected.title // ""')
  local selected_description
  selected_description=$(echo "$selection_json" | jq -r '.selected.description // ""')
  BLOCKED_IDS=$(echo "$selection_json" | jq -r '(.blocked // []) | map(.id) | join(", ")')
  UNKNOWN_DEP_IDS=$(echo "$selection_json" | jq -r '(.unknownDeps // []) | join(", ")')

  if [ -n "$UNKNOWN_DEP_IDS" ]; then
    echo "[Ralph] Warning: dependsOn references unknown task ids: $UNKNOWN_DEP_IDS" >&2
  fi

  if [ -z "$SELECTED_TASK_ID" ]; then
    echo "[Ralph] No unblocked tasks to pick; blocked by: ${BLOCKED_IDS:-none}" >&2
    return 0
  fi

  local selection_block
  selection_block=$(cat <<EOF
>>> Task Selection (iteration $iteration)
ID: $SELECTED_TASK_ID
Title: $SELECTED_TASK_TITLE
Description: $selected_description
EOF
)

  echo "$selection_block"

  if [ -n "$PROGRESS_FILE" ]; then
    {
      echo "## $(date --iso-8601=seconds) - Task selection (iteration $iteration)"
      echo "- ID: $SELECTED_TASK_ID"
      echo "- Title: $SELECTED_TASK_TITLE"
      echo "- Description: $selected_description"
      echo "- Blocked by: ${BLOCKED_IDS:-none}"
      [ -n "$UNKNOWN_DEP_IDS" ] && echo "- Unknown dependsOn: $UNKNOWN_DEP_IDS"
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

  if [ -z "$SELECTED_TASK_ID" ]; then
    echo "[Ralph] No unblocked tasks available; stopping." >&2
    exit 0
  fi

  local OUTPUT
  local merged_prompt
  local agents_block prompt_block specs_block

  if [ -n "$RESOLVED_AGENTS_FILE" ] && [ -f "$RESOLVED_AGENTS_FILE" ]; then
    agents_block=$(cat "$RESOLVED_AGENTS_FILE")
  else
    agents_block="### Missing AGENTS instructions\nNo AGENTS.md was found; proceed with caution."
  fi

  if [ -n "$RESOLVED_PROMPT_FILE" ] && [ -f "$RESOLVED_PROMPT_FILE" ]; then
    prompt_block=$(cat "$RESOLVED_PROMPT_FILE")
  else
    prompt_block="### Missing prompt instructions\nNo prompt.md was found; proceed with caution."
  fi

  specs_block=$(collect_ralph_specs)

  merged_prompt="$(printf "%s\n\n%s\n%s" "$agents_block" "$prompt_block" "$specs_block")"
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
    echo "Ralph requested stop at iteration $iteration. Attempt remediation before stopping whenever possible."
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
  require_runner_specs_dir || true
  require_agents_file || true
  require_prompt_file || true
  warn_if_target_instructions_present
  resolve_instruction_files
  echo "[Ralph] Roots: RALPH_ROOT=$RALPH_ROOT TARGET_REPO_ROOT=$TARGET_REPO_ROOT" >&2
  echo "[Ralph] Instruction lookup: runner files live under RALPH_ROOT; target-specific files live under TARGET_REPO_ROOT/.ralph" >&2
  log_instruction_fingerprints
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
