#!/bin/bash
# Ralph Wiggum - Lean AI loop
# Usage: ./ralph.sh [--tool opencode|amp|claude] [--opencode-model <model>] [--host-mode] [max_iterations]
# Orchestrates short agent runs driven by prompt.md and tasks.json, archiving old runs when the PRD changes.

set -euo pipefail

TOOL="opencode"
MAX_ITERATIONS=30
HOST_MODE=false
OPENCODE_MODEL="${OPENCODE_MODEL:-}"
RALPH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # location of this script and its dependencies
export RALPH_ROOT
TARGET_REPO_ROOT="" # target repo root where code will be generated
export TARGET_REPO_ROOT
RUNNER_AGENTS_FILE="$RALPH_ROOT/ralph-specs/AGENTS.md"
RESOLVED_AGENTS_FILE=""
RESOLVED_PROMPT_FILE=""
STATIC_PROMPT="" # built once in main, reused every iteration

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
      --host-mode)
        HOST_MODE=true
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

# ── Pushover notifications ──────────────────────────────────────────
send_notification() {
  local title="$1"
  local message="$2"
  local priority="${3:-0}"
  local notify_script="$RALPH_ROOT/scripts/notify.sh"

  if [ ! -x "$notify_script" ]; then
    return 0
  fi

  "$notify_script" "$title" "$message" "$priority" || true
}

_notify_context() {
  local project branch total_tasks completed remaining
  project=""
  branch=""
  total_tasks="${TOTAL_TASKS:-?}"
  completed="?"
  remaining="?"

  if command -v jq >/dev/null 2>&1 && [ -n "${PRD_FILE:-}" ] && [ -f "${PRD_FILE:-}" ]; then
    project=$(jq -r '.project // empty' "$PRD_FILE" 2>/dev/null || true)
    branch=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || true)
    remaining=$(jq '(.tasks // []) | map(select(.passes != true)) | length' "$PRD_FILE" 2>/dev/null || echo "?")
    if [ "$total_tasks" != "?" ] && [ "$remaining" != "?" ]; then
      completed=$((total_tasks - remaining))
    fi
  fi

  local ctx=""
  [ -n "$project" ] && ctx="${ctx}<b>Project:</b> ${project}\n"
  [ -n "$branch" ] && ctx="${ctx}<b>Branch:</b> ${branch}\n"
  ctx="${ctx}<b>Tool:</b> ${TOOL:-unknown}\n"
  ctx="${ctx}<b>Tasks:</b> ${completed}/${total_tasks} done"
  [ "$remaining" != "?" ] && [ "$remaining" != "0" ] && ctx="${ctx} (${remaining} remaining)"
  ctx="${ctx}\n"
  if [ -n "${LOOP_START_SECS:-}" ]; then
    local now elapsed_str
    now=$(date +%s)
    elapsed_str=$(format_duration $((now - LOOP_START_SECS)) 2>/dev/null || echo "?")
    ctx="${ctx}<b>Elapsed:</b> ${elapsed_str}\n"
  fi
  printf '%b' "$ctx"
}

notify_and_exit() {
  local code="$1"
  local reason_title="$2"
  local reason_detail="$3"
  local priority="${4:-0}"

  local context
  context=$(_notify_context 2>/dev/null || true)
  local message="${reason_detail}\n\n${context}"

  send_notification "$reason_title" "$(printf '%b' "$message")" "$priority"
  exit "$code"
}

validate_tool() {
  if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "opencode" ]]; then
    echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'opencode'."
    notify_and_exit 1 "Ralph: Invalid Tool" "Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'opencode'." 0
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
    notify_and_exit 1 "Ralph: Config Error" "TARGET_REPO is empty; specify --target-repo or set TARGET_REPO." 0
  fi

  if ! TARGET_REPO="$(cd "$target_repo_input" 2>/dev/null && pwd)"; then
    echo "TARGET_REPO path is invalid: $target_repo_input" >&2
    notify_and_exit 1 "Ralph: Config Error" "TARGET_REPO path is invalid: $target_repo_input" 0
  fi

  case "$TARGET_REPO" in
    "$RALPH_ROOT"|"$RALPH_ROOT"/*)
      echo "TARGET_REPO must not be the Ralph runner directory; point to a project repo containing .ralph." >&2
      echo "Resolved target: $TARGET_REPO" >&2
      notify_and_exit 1 "Ralph: Config Error" "TARGET_REPO must not be the Ralph runner directory.\nResolved target: $TARGET_REPO" 0
      ;;
  esac

  TARGET_REPO_ROOT="$TARGET_REPO"
  export TARGET_REPO_ROOT

  configure_prd_paths "$TARGET_REPO_ROOT"
}

require_agents_file() {
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

# Detect project languages in the target repo and return matching RULES files.
# Falls back to including all RULES files if detection is ambiguous.
detect_language_rules() {
  local rules_dir="$RALPH_ROOT/ralph-specs/code_generation_rules"
  local detected=()

  if [ ! -d "$rules_dir" ]; then
    return
  fi

  # Always include the general rules file
  if [ -f "$rules_dir/RULES.md" ]; then
    echo "$rules_dir/RULES.md"
  fi

  # Detect languages from target repo files
  local has_dotnet=false has_python=false has_node=false

  # Check for .NET
  if compgen -G "$TARGET_REPO_ROOT/*.sln" >/dev/null 2>&1 || \
     compgen -G "$TARGET_REPO_ROOT/*.csproj" >/dev/null 2>&1 || \
     compgen -G "$TARGET_REPO_ROOT/**/*.csproj" >/dev/null 2>&1 || \
     compgen -G "$TARGET_REPO_ROOT/src/**/*.csproj" >/dev/null 2>&1; then
    has_dotnet=true
  fi

  # Check for Python
  if [ -f "$TARGET_REPO_ROOT/pyproject.toml" ] || \
     [ -f "$TARGET_REPO_ROOT/setup.py" ] || \
     [ -f "$TARGET_REPO_ROOT/requirements.txt" ] || \
     [ -f "$TARGET_REPO_ROOT/Pipfile" ]; then
    has_python=true
  fi

  # Check for Node.js
  if [ -f "$TARGET_REPO_ROOT/package.json" ]; then
    has_node=true
  fi

  # Include matching language rules
  if $has_dotnet && [ -f "$rules_dir/RULES-dotnet.md" ]; then
    echo "$rules_dir/RULES-dotnet.md"
  fi

  if $has_python && [ -f "$rules_dir/RULES-python.md" ]; then
    echo "$rules_dir/RULES-python.md"
  fi

  # Fallback: if nothing detected, include all language rules
  if ! $has_dotnet && ! $has_python && ! $has_node; then
    echo "[Ralph] No language detected; including all RULES files." >&2
    for f in "$rules_dir"/RULES-*.md; do
      [ -f "$f" ] && echo "$f"
    done
  fi
}

# Build the static portion of the prompt (instructions + rules).
# Called once in main(). Per-iteration, only the task JSON and progress entry are injected.
build_static_prompt() {
  local prompt_block="" agents_block="" rules_block=""

  # Resolve prompt file
  if [ -n "$RESOLVED_PROMPT_FILE" ] && [ -f "$RESOLVED_PROMPT_FILE" ]; then
    prompt_block=$(cat "$RESOLVED_PROMPT_FILE")
  else
    prompt_block="### Missing prompt instructions\nNo prompt.md was found; proceed with caution."
  fi

  # Resolve agents file (now a thin pointer, but still included for tools that use it)
  if [ -n "$RESOLVED_AGENTS_FILE" ] && [ -f "$RESOLVED_AGENTS_FILE" ]; then
    agents_block=$(cat "$RESOLVED_AGENTS_FILE")
  else
    agents_block=""
  fi

  # Collect language-specific rules (C1: only matching languages)
  local rules_files
  rules_files=$(detect_language_rules)
  if [ -n "$rules_files" ]; then
    local file rel
    while IFS= read -r file; do
      [ -f "$file" ] || continue
      rel=${file#"$RALPH_ROOT/"}
      rules_block+=$(printf '\n### Begin %s\n' "$rel")
      rules_block+=$(cat "$file")
      rules_block+=$(printf '\n### End %s\n' "$rel")
    done <<< "$rules_files"
  fi

  # Host mode note injection
  local host_mode_note=""
  if [ "$HOST_MODE" = true ]; then
    host_mode_note="**Host mode is active.** You may run tools, tests, and builds directly on the host without containers. Container wrapping is not required this session."
  fi

  # Assemble static prompt: agents identity (thin) + prompt directive + rules
  # The prompt.md has {{HOST_MODE_NOTE}} placeholder for host-mode injection.
  # Use perl to avoid bash ${//} issues with & and \ in replacement strings.
  prompt_block=$(HOST_MODE_NOTE="$host_mode_note" perl -0777 -pe \
    's/\Q{{HOST_MODE_NOTE}}\E/$ENV{HOST_MODE_NOTE}/g' <<< "$prompt_block")

  if [ -n "$agents_block" ]; then
    STATIC_PROMPT="$(printf "%s\n\n%s\n%s" "$agents_block" "$prompt_block" "$rules_block")"
  else
    STATIC_PROMPT="$(printf "%s\n%s" "$prompt_block" "$rules_block")"
  fi

  echo "[Ralph] Static prompt built ($(echo -n "$STATIC_PROMPT" | wc -c) bytes)" >&2
}

# Extract the full JSON object for the selected task from tasks.json.
# Returns the complete task object with all fields (id, title, description, ACs, subtasks, keyFiles, etc.)
extract_selected_task_json() {
  local task_id="$1"

  if [ -z "$task_id" ] || [ ! -f "$PRD_FILE" ]; then
    echo "{}"
    return
  fi

  jq --arg id "$task_id" '(.tasks // [])[] | select(.id == $id)' "$PRD_FILE" 2>/dev/null || echo "{}"
}

# Extract the last progress entry from progress.md for context injection.
# Returns the last ## section (from last "## " heading to end or next "---").
extract_last_progress_entry() {
  if [ ! -f "$PROGRESS_FILE" ]; then
    echo "(No progress history yet)"
    return
  fi

  # Get everything after the last "## " heading
  local last_entry
  last_entry=$(awk '/^## /{buf=""; found=1} found{buf=buf ORS $0} END{if(found) print buf}' "$PROGRESS_FILE" 2>/dev/null || true)

  if [ -z "$last_entry" ]; then
    echo "(No progress entries yet)"
  else
    echo "$last_entry"
  fi
}

require_prompt_file() {
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
    notify_and_exit 1 "Ralph: Missing Prompt" "Missing prompt file at $PROMPT_FILE" 0
  fi
}

enforce_feature_branch() {
  if ! command -v git >/dev/null 2>&1; then
    echo "[Ralph] Branch enforcement failed: git not installed." >&2
    notify_and_exit 1 "Ralph: Setup Error" "Branch enforcement failed: git not installed." 0
  fi

  if [ ! -d "$TARGET_REPO_ROOT/.git" ]; then
    echo "[Ralph] Branch enforcement failed: $TARGET_REPO_ROOT is not a git repo." >&2
    notify_and_exit 1 "Ralph: Setup Error" "Branch enforcement failed: $TARGET_REPO_ROOT is not a git repo." 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "[Ralph] Branch enforcement failed: jq not installed to read branchName from PRD." >&2
    notify_and_exit 1 "Ralph: Setup Error" "Branch enforcement failed: jq not installed." 0
  fi

  local prd_branch
  prd_branch=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || true)

  if [ -z "$prd_branch" ]; then
    echo "[Ralph] PRD missing branchName; set a feature branch (e.g., ralph/<story-id>)." >&2
    notify_and_exit 1 "Ralph: PRD Error" "PRD missing branchName; set a feature branch." 0
  fi

  if [ "$prd_branch" = "main" ] || [ "$prd_branch" = "master" ]; then
    echo "[Ralph] PRD branchName cannot be main/master; use a dedicated feature branch." >&2
    notify_and_exit 1 "Ralph: PRD Error" "PRD branchName cannot be main/master; use a dedicated feature branch." 0
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
  notify_and_exit 1 "Ralph: Branch Error" "Could not switch to or create branch '$prd_branch'." 0
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
  SELECTED_TASK_JSON=""
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

  # B1: Extract full task JSON for prompt injection
  SELECTED_TASK_JSON=$(extract_selected_task_json "$SELECTED_TASK_ID")

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

# Assemble the per-iteration prompt by injecting the selected task and recent progress
# into the static prompt template.
build_iteration_prompt() {
  local task_json="$1"
  local last_progress="$2"
  local prompt="$STATIC_PROMPT"

  # Replace the {{SELECTED_TASK}} placeholder with actual task JSON
  local task_block
  if [ -n "$task_json" ] && [ "$task_json" != "{}" ]; then
    task_block=$(printf '```json\n%s\n```' "$task_json")
  else
    task_block="(No task injected — read .ralph/tasks.json to find the next unblocked task.)"
  fi

  # Replace the {{LAST_PROGRESS_ENTRY}} placeholder
  local progress_block
  if [ -n "$last_progress" ]; then
    progress_block="$last_progress"
  else
    progress_block="(No progress history yet)"
  fi

  # Use perl for placeholder replacement to avoid bash ${//} mangling
  # of & and \ characters in task JSON or progress text. Perl reads the
  # replacement from env vars so no shell escaping issues arise.
  prompt=$(TASK_BLOCK="$task_block" perl -0777 -pe \
    's/\Q{{SELECTED_TASK}}\E/$ENV{TASK_BLOCK}/g' <<< "$prompt")
  prompt=$(PROGRESS_BLOCK="$progress_block" perl -0777 -pe \
    's/\Q{{LAST_PROGRESS_ENTRY}}\E/$ENV{PROGRESS_BLOCK}/g' <<< "$prompt")

  printf '%s\n' "$prompt"
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
    notify_and_exit 0 "Ralph: No Unblocked Tasks" "No unblocked tasks available; all tasks may be done or blocked.\nStopping at iteration $iteration." 0
  fi

  # Stuck-task detection: same task selected repeatedly without progress
  if [ "$SELECTED_TASK_ID" = "$LAST_SELECTED_TASK" ]; then
    SAME_TASK_COUNT=$((SAME_TASK_COUNT + 1))
  else
    SAME_TASK_COUNT=1
    LAST_SELECTED_TASK="$SELECTED_TASK_ID"
  fi
  if [ "$SAME_TASK_COUNT" -ge "$MAX_SAME_TASK" ]; then
    echo "[Ralph] Task $SELECTED_TASK_ID selected $SAME_TASK_COUNT consecutive times without completing. Halting." >&2
    notify_and_exit 1 \
      "Ralph: Stuck Task" \
      "Task $SELECTED_TASK_ID selected $SAME_TASK_COUNT times without progress.\nAgent may be blocked on a task it cannot complete autonomously." \
      1
  fi

  # D4: Extract last progress entry for injection
  local last_progress
  last_progress=$(extract_last_progress_entry)

  # Build the per-iteration prompt (static + task + progress)
  local merged_prompt
  merged_prompt=$(build_iteration_prompt "$SELECTED_TASK_JSON" "$last_progress")

  local OUTPUT
  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cd "$TARGET_REPO_ROOT" && printf "%s" "$merged_prompt" | amp --dangerously-allow-all 2>&1 | tee >(cat >&2)) || true
  elif [[ "$TOOL" == "claude" ]]; then
    OUTPUT=$(cd "$TARGET_REPO_ROOT" && printf "%s" "$merged_prompt" | claude --dangerously-skip-permissions --print 2>&1 | tee >(cat >&2)) || true
  else
    local model_flag=""
    if [[ -n "$OPENCODE_MODEL" ]]; then
      model_flag="--model $OPENCODE_MODEL"
    fi
    OUTPUT=$(cd "$TARGET_REPO_ROOT" && printf "%s" "$merged_prompt" | opencode run $model_flag 2>&1 | tee >(cat >&2)) || true
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
    notify_and_exit 0 "Ralph: All Tasks Complete" "All tasks completed at iteration $iteration of $MAX_ITERATIONS.\n<b>Iteration time:</b> $(format_duration "$elapsed")\n<b>Total time:</b> $(format_duration "$loop_elapsed")" 0
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
    notify_and_exit 0 "Ralph: Stopped" "Agent requested stop at iteration $iteration of $MAX_ITERATIONS.\n<b>Iteration time:</b> $(format_duration "$elapsed")\n<b>Total time:</b> $(format_duration "$loop_elapsed")" 1
  fi

  # Permission rejection — the agent was denied access to a tool or directory.
  # This is unrecoverable without config changes; exit immediately with guidance.
  if echo "$OUTPUT" | grep -q "permission requested:.*auto-rejecting\|The user rejected permission to use this"; then
    echo "" >&2
    echo "========================================" >&2
    echo "FATAL: Permission rejected during iteration $iteration." >&2
    echo "The agent was denied a required permission and cannot continue." >&2
    echo "" >&2
    echo "To fix:" >&2
    echo "  1. Open ~/.config/opencode/opencode.json" >&2
    echo "  2. Ensure ALL permissions are set to \"allow\"" >&2
    echo "  3. Add your project path to external_directory:" >&2
    echo "     \"external_directory\": { \"/path/to/your/projects/**\": \"allow\" }" >&2
    echo "  4. Restart Ralph" >&2
    echo "========================================" >&2
    record_suggestions "$iteration" "permission_error" "$OUTPUT"
    local iter_end elapsed loop_elapsed
    iter_end=$(date +%s)
    elapsed=$((iter_end - iter_start))
    loop_elapsed=$((iter_end - LOOP_START_SECS))
    echo "[Ralph][timer] iteration=$iteration duration=$(format_duration "$elapsed") total_elapsed=$(format_duration "$loop_elapsed")" >&2
    notify_and_exit 1 "Ralph: Permission Error" "Agent was denied a required permission at iteration $iteration. Check opencode.json permissions." 1
  fi

  record_suggestions "$iteration" "continued" "$OUTPUT"

  # Reset stuck-task counter if the agent signaled TASK_COMPLETE or the task
  # flipped to passes:true (covers cases where the agent completes but the
  # promise tag is slightly malformed).
  if echo "$OUTPUT" | grep -q "<promise>TASK_COMPLETE</promise>"; then
    SAME_TASK_COUNT=0
  elif command -v jq >/dev/null 2>&1 && [ -f "$PRD_FILE" ] && [ -n "$SELECTED_TASK_ID" ]; then
    local task_passes
    task_passes=$(jq -r --arg id "$SELECTED_TASK_ID" \
      '(.tasks // [])[] | select(.id == $id) | .passes // false' "$PRD_FILE" 2>/dev/null || echo "false")
    if [ "$task_passes" = "true" ]; then
      SAME_TASK_COUNT=0
    fi
  fi

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
  echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS$([ "$HOST_MODE" = true ] && echo " [host-mode]")"

  # Stuck-task detection: halt if the same task is selected too many times
  # without completing. Guards against agents that fail to emit <promise>STOP</promise>.
  LAST_SELECTED_TASK=""
  SAME_TASK_COUNT=0
  MAX_SAME_TASK=3

  for i in $(seq 1 "$MAX_ITERATIONS"); do
    run_iteration "$i"
  done

  echo "Reached max iterations ($MAX_ITERATIONS) without completion."
  notify_and_exit 1 "Ralph: Max Iterations" "Reached max iterations ($MAX_ITERATIONS) without completing all tasks." 1
}

main() {
  parse_args "$@"
  validate_tool
  set_paths
  # Load .env from target repo if present (allows OPENCODE_MODEL override etc.)
  if [ -f "$TARGET_REPO_ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$TARGET_REPO_ROOT/.env"
    set +a
    echo "[Ralph] Loaded .env from $TARGET_REPO_ROOT/.env" >&2
  fi
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
  # B3: Build the static prompt once (instructions + rules); task context injected per-iteration
  build_static_prompt
  LOOP_START_SECS=$(date +%s)
  compute_total_tasks
  if [ "$HOST_MODE" = true ]; then
    echo "[Ralph] Host mode active: containers not required for tooling." >&2
  fi
  run_iterations
}

main "$@"
