#!/bin/bash
# Ralph Wiggum - Lean AI loop
# Usage: ./ralph.sh [--tool opencode|amp|claude] [--opencode-model <model>] [--cheap-model <model>] [--strong-model <model>] [--cheap-max-context <tokens>] [--strong-max-context <tokens>] [--sidecar|--no-sidecar] [--stop-sidecars-on-exit] [--target-repo path] [max_iterations]
# Orchestrates short agent runs driven by prompt.md and tasks.json, archiving old runs when the PRD changes.

set -euo pipefail

TOOL="opencode"
MAX_ITERATIONS=30
HOST_MODE=false
# Sidecar mode: long-lived per-project containers reused across iterations.
# Auto-enabled when Docker is available (see main()); set --no-sidecar to
# disable, or --sidecar to force on.
SIDECAR_MODE=false
SIDECAR_MODE_EXPLICIT=false
# Persist sidecars across ralph.sh sessions by default so the second and
# subsequent runs on the same repo start warm. Set --stop-sidecars-on-exit
# to opt into cleanup.
SIDECAR_STOP_ON_EXIT=false
OPENCODE_MODEL="${OPENCODE_MODEL:-}"
OPENCODE_MODEL_CHEAP="${OPENCODE_MODEL_CHEAP:-}"
OPENCODE_MODEL_STRONG="${OPENCODE_MODEL_STRONG:-}"
# Context capacity thresholds (approximate tokens) for tier auto-upgrade.
# When estimated prompt tokens exceed CHEAP_MAX, auto-upgrade to strong.
# Defaults tuned for typical performance sweet-spots (not absolute model limits):
#   cheap tier (Sonnet-class): degrades past ~48K, upgrade before that
#   strong tier (Opus-class): comfortable through ~120K
OPENCODE_MODEL_CHEAP_MAX_CONTEXT="${OPENCODE_MODEL_CHEAP_MAX_CONTEXT:-48000}"
OPENCODE_MODEL_STRONG_MAX_CONTEXT="${OPENCODE_MODEL_STRONG_MAX_CONTEXT:-120000}"
# Context expansion factor: multiplies the initial prompt token estimate to
# approximate the runtime context after tool calls, file reads, and edits.
# Base factor + (keyFiles_count / 2). Tunable via env var.
RALPH_CONTEXT_EXPANSION_BASE="${RALPH_CONTEXT_EXPANSION_BASE:-2}"
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
      --cheap-model)
        OPENCODE_MODEL_CHEAP="$2"
        shift 2
        ;;
      --cheap-model=*)
        OPENCODE_MODEL_CHEAP="${1#*=}"
        shift
        ;;
      --strong-model)
        OPENCODE_MODEL_STRONG="$2"
        shift 2
        ;;
      --strong-model=*)
        OPENCODE_MODEL_STRONG="${1#*=}"
        shift
        ;;
      --cheap-max-context)
        OPENCODE_MODEL_CHEAP_MAX_CONTEXT="$2"
        shift 2
        ;;
      --cheap-max-context=*)
        OPENCODE_MODEL_CHEAP_MAX_CONTEXT="${1#*=}"
        shift
        ;;
      --strong-max-context)
        OPENCODE_MODEL_STRONG_MAX_CONTEXT="$2"
        shift 2
        ;;
      --strong-max-context=*)
        OPENCODE_MODEL_STRONG_MAX_CONTEXT="${1#*=}"
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
        echo "[Ralph][error] --host-mode is disabled. All runtime commands must run in containers." >&2
        echo "[Ralph]         Set up Docker/Podman and re-run without --host-mode." >&2
        exit 2
        ;;
      --sidecar)
        SIDECAR_MODE=true
        SIDECAR_MODE_EXPLICIT=true
        shift
        ;;
      --no-sidecar)
        SIDECAR_MODE=false
        SIDECAR_MODE_EXPLICIT=true
        shift
        ;;
      --stop-sidecars-on-exit)
        SIDECAR_STOP_ON_EXIT=true
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
     find "$TARGET_REPO_ROOT" -maxdepth 4 -name "*.csproj" -print -quit 2>/dev/null | grep -q .; then
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

  # Resolve agents file — kept for resolution/fingerprinting but NOT injected into
  # the iteration prompt (it's meta-runner documentation, not useful to the iteration agent).
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

  # Sidecar mode note injection
  local sidecar_mode_note=""
  if [ "$SIDECAR_MODE" = true ]; then
    sidecar_mode_note="**Sidecar mode is active.** Long-lived containers are running for this session. Use \`docker exec <container-name> <cmd>\` instead of \`docker run --rm\`. Available sidecars: \${RALPH_SIDECAR_NODE:-none}, \${RALPH_SIDECAR_PYTHON:-none}, \${RALPH_SIDECAR_DOTNET:-none}."
  fi

  # Assemble static prompt: agents identity (thin) + prompt directive + rules
  # The prompt.md has {{SIDECAR_MODE_NOTE}} placeholder.
  prompt_block=$(SIDECAR_MODE_NOTE="$sidecar_mode_note" perl -0777 -pe \
    's/\Q{{SIDECAR_MODE_NOTE}}\E/$ENV{SIDECAR_MODE_NOTE}/g' <<< "$prompt_block")

  # Conditional cert/nuget injection — only include when project uses containers/Dockerfiles
  local cert_rules_content="" nuget_rules_content=""
  local has_dockerfiles=false has_dotnet_project=false

  if compgen -G "$TARGET_REPO_ROOT/Dockerfile*" >/dev/null 2>&1 || \
     find "$TARGET_REPO_ROOT" -maxdepth 4 -name "Dockerfile*" -print -quit 2>/dev/null | grep -q . || \
     compgen -G "$TARGET_REPO_ROOT/docker-compose*" >/dev/null 2>&1; then
    has_dockerfiles=true
  fi

  if compgen -G "$TARGET_REPO_ROOT/*.sln" >/dev/null 2>&1 || \
     find "$TARGET_REPO_ROOT" -maxdepth 4 -name "*.csproj" -print -quit 2>/dev/null | grep -q .; then
    has_dotnet_project=true
  fi

  local cert_rules_file="$RALPH_ROOT/ralph-specs/CERT_RULES.md"
  local nuget_rules_file="$RALPH_ROOT/ralph-specs/NUGET_RULES.md"

  if [ "$has_dockerfiles" = true ] && [ -f "$cert_rules_file" ]; then
    cert_rules_content=$(cat "$cert_rules_file")
    echo "[Ralph] Cert rules included (Dockerfiles detected)" >&2
  else
    cert_rules_content="(Cert rules omitted — no Dockerfiles detected. See \$RALPH_ROOT/ralph-specs/CERT_RULES.md if building containers.)"
  fi

  if [ "$has_dotnet_project" = true ] && [ -f "$nuget_rules_file" ]; then
    nuget_rules_content=$(cat "$nuget_rules_file")
    echo "[Ralph] NuGet rules included (.NET project detected)" >&2
  else
    nuget_rules_content=""
  fi

  prompt_block=$(CERT_RULES="$cert_rules_content" perl -0777 -pe \
    's/\Q{{CERT_RULES}}\E/$ENV{CERT_RULES}/g' <<< "$prompt_block")
  prompt_block=$(NUGET_RULES="$nuget_rules_content" perl -0777 -pe \
    's/\Q{{NUGET_RULES}}\E/$ENV{NUGET_RULES}/g' <<< "$prompt_block")

  # Language-gated blocks: strip {{#IF_LANG}}...{{/IF_LANG}} sections whose language isn't present.
  # Detect languages in target repo.
  local has_node_lang=false has_python_lang=false has_dotnet_lang=false
  [ -f "$TARGET_REPO_ROOT/package.json" ] && has_node_lang=true
  if [ -f "$TARGET_REPO_ROOT/pyproject.toml" ] || [ -f "$TARGET_REPO_ROOT/requirements.txt" ] || \
     [ -f "$TARGET_REPO_ROOT/setup.py" ] || [ -f "$TARGET_REPO_ROOT/Pipfile" ]; then
    has_python_lang=true
  fi
  if compgen -G "$TARGET_REPO_ROOT/*.sln" >/dev/null 2>&1 || \
     compgen -G "$TARGET_REPO_ROOT/*.csproj" >/dev/null 2>&1 || \
     find "$TARGET_REPO_ROOT" -maxdepth 4 -name "*.csproj" -print -quit 2>/dev/null | grep -q .; then
    has_dotnet_lang=true
  fi

  # If no language detected, keep all blocks (safe fallback for scaffold scenarios).
  local keep_all=false
  if ! $has_node_lang && ! $has_python_lang && ! $has_dotnet_lang; then
    keep_all=true
    echo "[Ralph] No language detected; keeping all language-gated prompt blocks." >&2
  fi

  strip_or_keep_block() {
    local lang="$1" keep="$2" content="$3"
    if [ "$keep" = true ]; then
      # Strip only the markers, keep content
      LANG_TAG="$lang" perl -0777 -pe 's/\{\{#IF_\Q$ENV{LANG_TAG}\E\}\}\n?//g; s/\{\{\/IF_\Q$ENV{LANG_TAG}\E\}\}\n?//g' <<< "$content"
    else
      # Remove entire block including markers
      LANG_TAG="$lang" perl -0777 -pe 's/\{\{#IF_\Q$ENV{LANG_TAG}\E\}\}.*?\{\{\/IF_\Q$ENV{LANG_TAG}\E\}\}\n?//gs' <<< "$content"
    fi
  }

  keep_node=false; keep_python=false; keep_dotnet=false
  if [ "$keep_all" = true ]; then
    keep_node=true; keep_python=true; keep_dotnet=true
  else
    $has_node_lang   && keep_node=true
    $has_python_lang && keep_python=true
    $has_dotnet_lang && keep_dotnet=true
  fi

  prompt_block=$(strip_or_keep_block "NODE"   "$keep_node"   "$prompt_block")
  prompt_block=$(strip_or_keep_block "PYTHON" "$keep_python" "$prompt_block")
  prompt_block=$(strip_or_keep_block "DOTNET" "$keep_dotnet" "$prompt_block")

  if [ "$keep_all" = false ]; then
    local langs=""
    $has_node_lang && langs="$langs node"
    $has_python_lang && langs="$langs python"
    $has_dotnet_lang && langs="$langs dotnet"
    echo "[Ralph] Language-gated prompt blocks kept for:${langs}" >&2
  fi

  # Extracted-section refs (short summary + optional file path). Agent reads the
  # file only when it actually needs the full content — minimal cost when unused.
  local eh_ref browser_ref
  local eh_file="$RALPH_ROOT/ralph-specs/error-handling.md"
  local browser_file="$RALPH_ROOT/ralph-specs/browser-verification.md"

  if [ -f "$eh_file" ]; then
    eh_ref="Full decision table with all exit cases: read \`$eh_file\` only if the summary above is insufficient for the current situation."
  else
    eh_ref=""
  fi

  # Browser verification: only reference the file if any task in tasks.json
  # mentions a browser-related AC. Matches "dev-browser" or "browser" (case-insensitive)
  # to catch variant phrasings.
  local tasks_file="$TARGET_REPO_ROOT/.ralph/tasks.json"
  if [ -f "$tasks_file" ] && grep -qiE "dev-browser|browser" "$tasks_file" 2>/dev/null; then
    browser_ref="Browser AC present in this PRD. Read \`$browser_file\` for the exact handling pattern (dev-browser skill vs. manual verification block + STOP)."
    echo "[Ralph] Browser verification reference included (browser AC detected)" >&2
  else
    browser_ref="(No browser ACs in this PRD — section omitted.)"
  fi

  prompt_block=$(EH_REF="$eh_ref" perl -0777 -pe \
    's/\Q{{ERROR_HANDLING_REF}}\E/$ENV{EH_REF}/g' <<< "$prompt_block")
  prompt_block=$(BROWSER_REF="$browser_ref" perl -0777 -pe \
    's/\Q{{BROWSER_VERIFICATION_REF}}\E/$ENV{BROWSER_REF}/g' <<< "$prompt_block")

  # Assemble static prompt: prompt directive + rules (agents_block excluded per Expert #3/#4 review)
  STATIC_PROMPT="$(printf "%s\n%s" "$prompt_block" "$rules_block")"

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
# Capped at RALPH_PROGRESS_INJECT_MAX_CHARS to prevent unbounded growth eating
# iteration context budget.
RALPH_PROGRESS_INJECT_MAX_CHARS="${RALPH_PROGRESS_INJECT_MAX_CHARS:-2000}"

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
    return
  fi

  # Cap size to avoid injecting bloat
  local entry_size
  entry_size=$(echo -n "$last_entry" | wc -c)
  if [ "$entry_size" -gt "$RALPH_PROGRESS_INJECT_MAX_CHARS" ]; then
    # Take first N chars, add truncation marker
    echo "$last_entry" | head -c "$RALPH_PROGRESS_INJECT_MAX_CHARS"
    echo ""
    echo "... [truncated: entry was $entry_size chars, capped at $RALPH_PROGRESS_INJECT_MAX_CHARS]"
  else
    echo "$last_entry"
  fi
}

# Resolve the model to use for this iteration based on tier.
# Priority: task.tier field > heuristic > OPENCODE_MODEL > default.
# Returns the model string (or empty for default).
resolve_iteration_model() {
  local task_json="$1"
  local is_retry="${2:-false}"
  local estimated_tokens="${3:-0}"

  # If OPENCODE_MODEL is set and no tiering configured, use it directly
  if [ -n "$OPENCODE_MODEL" ] && [ -z "$OPENCODE_MODEL_CHEAP" ] && [ -z "$OPENCODE_MODEL_STRONG" ]; then
    echo "$OPENCODE_MODEL"
    return
  fi

  # If no tiering configured at all, return empty (use tool default)
  if [ -z "$OPENCODE_MODEL_CHEAP" ] && [ -z "$OPENCODE_MODEL_STRONG" ]; then
    echo "$OPENCODE_MODEL"
    return
  fi

  # Auto-promote to strong on retry (stuck-task escalation)
  if [ "$is_retry" = "true" ] && [ -n "$OPENCODE_MODEL_STRONG" ]; then
    echo "[Ralph][tier] Escalating to strong model on retry" >&2
    echo "$OPENCODE_MODEL_STRONG"
    return
  fi

  # Determine initial tier (before context check)
  local chosen_tier="" chosen_model=""

  # Check task.tier field first (PRD-driven)
  local task_tier=""
  if [ -n "$task_json" ] && [ "$task_json" != "{}" ] && command -v jq >/dev/null 2>&1; then
    task_tier=$(echo "$task_json" | jq -r '.tier // ""' 2>/dev/null || true)
  fi

  if [ "$task_tier" = "strong" ] && [ -n "$OPENCODE_MODEL_STRONG" ]; then
    chosen_tier="strong"; chosen_model="$OPENCODE_MODEL_STRONG"
    echo "[Ralph][tier] Initial: strong model (PRD-driven)" >&2
  elif [ "$task_tier" = "cheap" ] && [ -n "$OPENCODE_MODEL_CHEAP" ]; then
    chosen_tier="cheap"; chosen_model="$OPENCODE_MODEL_CHEAP"
    echo "[Ralph][tier] Initial: cheap model (PRD-driven)" >&2
  else
    # Heuristic fallback: strong only for genuinely complex tasks.
    #
    # Previous rule ("ACs mention test|verify") fired on nearly every task
    # because stock ACs include "Typecheck passes" / "Tests pass". Analysis
    # of ~46 real iterations showed cheap tier succeeding 8/9 times when
    # used, so the old rule was silently forcing strong tier ~90% of the
    # time despite cheap being adequate.
    #
    # New rule (any of):
    #   - >=6 keyFiles (broad change surface), OR
    #   - description/notes/ACs signal genuinely hard work: refactor,
    #     migrate, redesign, algorithm, concurrency, performance, security,
    #     architecture
    #
    # Boilerplate ACs like "Typecheck passes" / "Tests pass" no longer
    # promote to strong on their own. Use .tier = "strong" in the PRD to
    # force strong for tasks the heuristic can't detect.
    local use_strong=false
    if [ -n "$task_json" ] && [ "$task_json" != "{}" ] && command -v jq >/dev/null 2>&1; then
      local key_files_count complex_signal
      key_files_count=$(echo "$task_json" | jq '(.keyFiles // []) | length' 2>/dev/null || echo 0)
      complex_signal=$(echo "$task_json" | jq '
        [(.title // ""), (.description // ""), (.implementationNotes // "")]
        + ((.acceptanceCriteria // []))
        | map(ascii_downcase)
        | any(test("refactor|migrat|redesign|algorithm|concurren|performance|security|architecture|openiddict|oauth|oidc|jwks|signing key|options ?monitor|postconfigure|ipostconfigure|event ?handler|dependency injection|reflection|expression tree"))
      ' 2>/dev/null || echo "false")
      if [ "$key_files_count" -ge 6 ] 2>/dev/null || [ "$complex_signal" = "true" ]; then
        use_strong=true
      fi
    fi

    if [ "$use_strong" = "true" ] && [ -n "$OPENCODE_MODEL_STRONG" ]; then
      chosen_tier="strong"; chosen_model="$OPENCODE_MODEL_STRONG"
      echo "[Ralph][tier] Initial: strong model (heuristic: keyFiles≥5 or ACs mention tests)" >&2
    elif [ -n "$OPENCODE_MODEL_CHEAP" ]; then
      chosen_tier="cheap"; chosen_model="$OPENCODE_MODEL_CHEAP"
      echo "[Ralph][tier] Initial: cheap model (heuristic)" >&2
    else
      chosen_tier="strong"; chosen_model="$OPENCODE_MODEL_STRONG"
    fi
  fi

  # Context-size auto-upgrade: if estimated tokens exceed cheap tier's comfort
  # zone, upgrade to strong (or warn if already strong and near strong's limit).
  if [ "$estimated_tokens" -gt 0 ] 2>/dev/null; then
    if [ "$chosen_tier" = "cheap" ] && [ "$estimated_tokens" -gt "$OPENCODE_MODEL_CHEAP_MAX_CONTEXT" ] 2>/dev/null; then
      if [ -n "$OPENCODE_MODEL_STRONG" ]; then
        echo "[Ralph][tier] Auto-upgrade cheap→strong: estimated $estimated_tokens tokens exceeds cheap max ($OPENCODE_MODEL_CHEAP_MAX_CONTEXT)" >&2
        chosen_model="$OPENCODE_MODEL_STRONG"
      else
        echo "[Ralph][tier] WARN: estimated $estimated_tokens tokens exceeds cheap max but no strong model configured" >&2
      fi
    elif [ "$chosen_tier" = "strong" ] && [ "$estimated_tokens" -gt "$OPENCODE_MODEL_STRONG_MAX_CONTEXT" ] 2>/dev/null; then
      echo "[Ralph][tier] WARN: estimated $estimated_tokens tokens exceeds strong max ($OPENCODE_MODEL_STRONG_MAX_CONTEXT); performance may degrade" >&2
    fi
  fi

  echo "$chosen_model"
}

# Inline small keyFiles from the task into the prompt to avoid tool-call round-trips.
# Returns a block of <file> tags for files that exist and are under the size threshold.
RALPH_MAX_INLINE_BYTES="${RALPH_MAX_INLINE_BYTES:-8000}"

inline_keyfiles() {
  local task_json="$1"
  local result=""

  if [ -z "$task_json" ] || [ "$task_json" = "{}" ]; then
    echo ""
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo ""
    return
  fi

  local files
  files=$(echo "$task_json" | jq -r '(.keyFiles // [])[]' 2>/dev/null || true)

  if [ -z "$files" ]; then
    echo ""
    return
  fi

  while IFS= read -r filepath; do
    # Skip files marked (create new)
    if [[ "$filepath" == *"(create new)"* ]]; then
      continue
    fi

    # Resolve relative to target repo
    local full_path="$TARGET_REPO_ROOT/$filepath"
    if [ ! -f "$full_path" ]; then
      continue
    fi

    local size
    size=$(stat -c%s "$full_path" 2>/dev/null || stat -f%z "$full_path" 2>/dev/null || echo 999999)
    if [ "$size" -le "$RALPH_MAX_INLINE_BYTES" ] 2>/dev/null; then
      result+=$(printf '\n<file path="%s">\n' "$filepath")
      result+=$(cat "$full_path")
      result+=$(printf '\n</file>\n')
    fi
  done <<< "$files"

  echo "$result"
}

# ── Sidecar containers ──────────────────────────────────────────────
# Long-lived per-repo containers reused across iterations AND across
# ralph.sh sessions. Named deterministically from the target repo path so
# repeated sessions reuse the same warm containers.
SIDECAR_IDS=()
SIDECAR_NAMES=()

# Compute a stable short hash of the target repo path for sidecar names.
sidecar_repo_tag() {
  local abs
  abs=$(cd "$TARGET_REPO_ROOT" 2>/dev/null && pwd || echo "$TARGET_REPO_ROOT")
  printf '%s' "$abs" | sha1sum | awk '{print substr($1, 1, 10)}'
}

# Auto-enable sidecar mode when Docker is available and the user didn't say
# otherwise. Sidecars slash cold-start cost across iterations; there is no
# downside for the default case (single-user local iteration).
auto_enable_sidecar_mode() {
  if [ "$SIDECAR_MODE_EXPLICIT" = true ]; then
    return
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "[Ralph][sidecar] Docker not found; sidecar mode disabled." >&2
    return
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "[Ralph][sidecar] Docker not reachable; sidecar mode disabled." >&2
    return
  fi
  SIDECAR_MODE=true
  echo "[Ralph][sidecar] Sidecar mode auto-enabled (Docker available). Use --no-sidecar to disable." >&2
}

# Start a single sidecar if not already running.
# Args: name image [extra_docker_args]
# Sets a global RALPH_SIDECAR_<UPPER> to the name on success.
_start_sidecar_if_needed() {
  local name="$1" image="$2" export_var="$3"
  shift 3
  local extra=("$@")

  # Reuse if already running, unless the running container is missing an env
  # var that we're now trying to inject (stale sidecar from an earlier run).
  # This is the common case that silently breaks NuGet: sidecar was started
  # before NUGET_PRIVATE_FEED_URL / PROGET_DOTNET_TOKEN were exported, so it
  # keeps trying api.nuget.org and getting reset by the corp proxy.
  local existing_state
  existing_state=$(docker inspect --format='{{.State.Running}}' "$name" 2>/dev/null || echo "missing")
  if [ "$existing_state" = "true" ]; then
    local stale=false expected_env
    for expected_env in "${extra[@]}"; do
      case "$expected_env" in
        -e)
          continue
          ;;
        *=*)
          local key="${expected_env%%=*}"
          # Only enforce presence of NuGet/cert-critical vars; other vars are
          # optional to re-check.
          case "$key" in
            NUGET_PRIVATE_FEED_URL|PROGET_DOTNET_TOKEN|PROXY_CERT_URL|ISSUING_CA_CERT_URL|ROOT_CA_CERT_URL)
              if ! docker exec "$name" bash -c "[ -n \"\${$key:-}\" ]" >/dev/null 2>&1; then
                stale=true
                echo "[Ralph][sidecar] $name missing $key; recreating" >&2
                break
              fi
              ;;
          esac
          ;;
      esac
    done
    if [ "$stale" = true ]; then
      docker rm -f "$name" >/dev/null 2>&1 || true
    else
      echo "[Ralph][sidecar] Reusing running $name" >&2
      SIDECAR_NAMES+=("$name")
      export "$export_var=$name"
      return 0
    fi
  fi

  # If it exists but is stopped, start it.
  if [ "$existing_state" = "false" ]; then
    if docker start "$name" >/dev/null 2>&1; then
      echo "[Ralph][sidecar] Restarted stopped $name" >&2
      SIDECAR_NAMES+=("$name")
      export "$export_var=$name"
      return 0
    fi
    # Corrupted; remove and recreate below.
    docker rm -f "$name" >/dev/null 2>&1 || true
  fi

  # Fresh create.
  if docker run -d --name "$name" --memory=4g --cpus=2 \
      -v "$TARGET_REPO_ROOT":/work -w /work \
      "${extra[@]}" \
      "$image" sleep infinity >/dev/null 2>&1; then
    echo "[Ralph][sidecar] Started $name ($image)" >&2
    SIDECAR_NAMES+=("$name")
    SIDECAR_IDS+=("$name")   # track for optional cleanup
    export "$export_var=$name"
    return 0
  fi
  echo "[Ralph][sidecar] Failed to start $name" >&2
  return 1
}

# Fire-and-forget cache warming inside a sidecar.
# Runs in background; the first iteration may still race it, but subsequent
# iterations start warm. Failures are silent — cache warming is best-effort.
_warm_sidecar_cache() {
  local name="$1" cmd="$2"
  ( docker exec "$name" bash -lc "$cmd" >/dev/null 2>&1 || true ) &
}

launch_sidecars() {
  if [ "$SIDECAR_MODE" != true ]; then
    return
  fi

  echo "[Ralph][sidecar] Preparing sidecars for $TARGET_REPO_ROOT..." >&2

  local has_node=false has_python=false has_dotnet=false
  [ -f "$TARGET_REPO_ROOT/package.json" ] && has_node=true
  if [ -f "$TARGET_REPO_ROOT/pyproject.toml" ] || [ -f "$TARGET_REPO_ROOT/requirements.txt" ]; then
    has_python=true
  fi
  if compgen -G "$TARGET_REPO_ROOT/*.sln" >/dev/null 2>&1 || \
     find "$TARGET_REPO_ROOT" -maxdepth 4 -name "*.csproj" -print -quit 2>/dev/null | grep -q .; then
    has_dotnet=true
  fi

  local tag
  tag=$(sidecar_repo_tag)

  # Launch all sidecars in parallel so start-up is bounded by the slowest,
  # not the sum. Wait for all subshells before moving on.
  local pids=()
  if [ "$has_node" = true ]; then
    ( _start_sidecar_if_needed "ralph-sidecar-node-$tag" "node:20" "RALPH_SIDECAR_NODE" \
        -v "ralph-cache-node-$tag:/work/node_modules" ) & pids+=($!)
  fi
  if [ "$has_python" = true ]; then
    ( _start_sidecar_if_needed "ralph-sidecar-python-$tag" "python:3.11" "RALPH_SIDECAR_PYTHON" \
        -v "ralph-cache-pip-$tag:/root/.cache/pip" ) & pids+=($!)
  fi
  if [ "$has_dotnet" = true ]; then
    # Forward NuGet feed + ProGet token + corporate cert URLs so `dotnet restore`
    # inside the sidecar reaches the private feed instead of falling back to
    # nuget.org (which the corporate proxy drops from containers).
    # Mount nuget.config into the container. Prefer the target repo's own
    # .ralph/nuget.config (typically <clear/> + ProGet-only, which forces all
    # restore traffic through ProGet). Fall back to the shared runner copy
    # only when the target repo hasn't provided its own — note that copy
    # includes api.nuget.org, which will fail behind the corp proxy.
    local dotnet_extra=(
      -v "ralph-cache-nuget-$tag:/root/.nuget/packages"
    )
    if [ -f "$TARGET_REPO_ROOT/.ralph/nuget.config" ]; then
      dotnet_extra+=(-v "$TARGET_REPO_ROOT/.ralph/nuget.config:/work/nuget.config:ro")
      echo "[Ralph][sidecar] Using target repo's .ralph/nuget.config for dotnet sidecar" >&2
    elif [ -f "$RALPH_ROOT/ralph-specs/resources/nuget.config" ]; then
      dotnet_extra+=(-v "$RALPH_ROOT/ralph-specs/resources/nuget.config:/work/nuget.config:ro")
      echo "[Ralph][sidecar] WARN: no .ralph/nuget.config in target repo; using shared runner nuget.config (includes api.nuget.org — will fail behind corp proxies)" >&2
    fi
    [ -n "${NUGET_PRIVATE_FEED_URL:-}" ] && dotnet_extra+=(-e "NUGET_PRIVATE_FEED_URL=$NUGET_PRIVATE_FEED_URL")
    [ -n "${PROGET_DOTNET_TOKEN:-}" ]    && dotnet_extra+=(-e "PROGET_DOTNET_TOKEN=$PROGET_DOTNET_TOKEN")
    [ -n "${PROXY_CERT_URL:-}" ]         && dotnet_extra+=(-e "PROXY_CERT_URL=$PROXY_CERT_URL")
    [ -n "${ISSUING_CA_CERT_URL:-}" ]    && dotnet_extra+=(-e "ISSUING_CA_CERT_URL=$ISSUING_CA_CERT_URL")
    [ -n "${ROOT_CA_CERT_URL:-}" ]       && dotnet_extra+=(-e "ROOT_CA_CERT_URL=$ROOT_CA_CERT_URL")

    ( _start_sidecar_if_needed "ralph-sidecar-dotnet-$tag" "mcr.microsoft.com/dotnet/sdk:8.0" "RALPH_SIDECAR_DOTNET" \
        "${dotnet_extra[@]}" ) & pids+=($!)
  fi

  # Wait for all sidecar starts. Note: `export` inside a background subshell
  # does not propagate; the sidecar names are stable per (repo, language) so
  # we re-derive them below rather than rely on the subshell exports.
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Re-derive names in the parent shell (subshell exports were lost).
  if [ "$has_node" = true ]; then
    if docker inspect --format='{{.State.Running}}' "ralph-sidecar-node-$tag" 2>/dev/null | grep -q true; then
      export RALPH_SIDECAR_NODE="ralph-sidecar-node-$tag"
      SIDECAR_NAMES+=("$RALPH_SIDECAR_NODE")
    fi
  fi
  if [ "$has_python" = true ]; then
    if docker inspect --format='{{.State.Running}}' "ralph-sidecar-python-$tag" 2>/dev/null | grep -q true; then
      export RALPH_SIDECAR_PYTHON="ralph-sidecar-python-$tag"
      SIDECAR_NAMES+=("$RALPH_SIDECAR_PYTHON")
    fi
  fi
  if [ "$has_dotnet" = true ]; then
    if docker inspect --format='{{.State.Running}}' "ralph-sidecar-dotnet-$tag" 2>/dev/null | grep -q true; then
      export RALPH_SIDECAR_DOTNET="ralph-sidecar-dotnet-$tag"
      SIDECAR_NAMES+=("$RALPH_SIDECAR_DOTNET")
    fi
  fi

  if [ ${#SIDECAR_NAMES[@]} -eq 0 ]; then
    echo "[Ralph][sidecar] No sidecars running." >&2
    return
  fi

  # Background dependency-cache warming. Best-effort; the first iteration may
  # start before warming completes, but subsequent iterations reuse the cache.
  if [ -n "${RALPH_SIDECAR_NODE:-}" ] && [ -f "$TARGET_REPO_ROOT/package-lock.json" ]; then
    _warm_sidecar_cache "$RALPH_SIDECAR_NODE" "npm ci --prefer-offline --no-audit --progress=false"
  elif [ -n "${RALPH_SIDECAR_NODE:-}" ] && [ -f "$TARGET_REPO_ROOT/package.json" ]; then
    _warm_sidecar_cache "$RALPH_SIDECAR_NODE" "npm install --prefer-offline --no-audit --progress=false"
  fi
  if [ -n "${RALPH_SIDECAR_PYTHON:-}" ] && [ -f "$TARGET_REPO_ROOT/requirements.txt" ]; then
    _warm_sidecar_cache "$RALPH_SIDECAR_PYTHON" "pip install --disable-pip-version-check -q -r requirements.txt"
  elif [ -n "${RALPH_SIDECAR_PYTHON:-}" ] && [ -f "$TARGET_REPO_ROOT/pyproject.toml" ]; then
    _warm_sidecar_cache "$RALPH_SIDECAR_PYTHON" "pip install --disable-pip-version-check -q -e . 2>/dev/null || pip install --disable-pip-version-check -q ."
  fi
  if [ -n "${RALPH_SIDECAR_DOTNET:-}" ]; then
    _warm_sidecar_cache "$RALPH_SIDECAR_DOTNET" "dotnet restore --nologo"
  fi

  echo "[Ralph][sidecar] ${#SIDECAR_NAMES[@]} sidecar(s) ready. Cache warming running in background." >&2
}

# Cleanup sidecars ONLY when the user opted in with --stop-sidecars-on-exit.
# Default is to persist so the next ralph.sh session on this repo starts
# warm (a rerun otherwise pays ~10-30s of docker/dep startup per language).
cleanup_sidecars() {
  if [ "$SIDECAR_STOP_ON_EXIT" != true ]; then
    if [ ${#SIDECAR_NAMES[@]} -gt 0 ]; then
      echo "[Ralph][sidecar] Leaving ${#SIDECAR_NAMES[@]} sidecar(s) running for next session. Use --stop-sidecars-on-exit to auto-remove." >&2
    fi
    return
  fi
  if [ ${#SIDECAR_NAMES[@]} -eq 0 ]; then
    return
  fi
  echo "[Ralph][sidecar] Removing sidecar containers..." >&2
  for name in "${SIDECAR_NAMES[@]}"; do
    docker rm -f "$name" >/dev/null 2>&1 || true
  done
  SIDECAR_NAMES=()
  SIDECAR_IDS=()
}

# Check sidecar containers are still running; restart any that died.
check_sidecars() {
  if [ "$SIDECAR_MODE" != true ] || [ ${#SIDECAR_NAMES[@]} -eq 0 ]; then
    return
  fi

  local tag
  tag=$(sidecar_repo_tag)

  for name in "${SIDECAR_NAMES[@]}"; do
    if docker inspect --format='{{.State.Running}}' "$name" 2>/dev/null | grep -q "true"; then
      continue
    fi
    echo "[Ralph][sidecar] Container $name died; restarting..." >&2
    # Determine image from the name convention.
    local image=""
    case "$name" in
      ralph-sidecar-node-*)   image="node:20" ;;
      ralph-sidecar-python-*) image="python:3.11" ;;
      ralph-sidecar-dotnet-*) image="mcr.microsoft.com/dotnet/sdk:8.0" ;;
    esac
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker run -d --name "$name" --memory=4g --cpus=2 \
      -v "$TARGET_REPO_ROOT":/work -w /work \
      "$image" sleep infinity >/dev/null 2>&1 || \
      echo "[Ralph][sidecar] Failed to restart $name" >&2
  done
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

  # Inline small keyFiles to reduce tool-call round-trips
  local inlined_files
  inlined_files=$(inline_keyfiles "$task_json")
  if [ -n "$inlined_files" ]; then
    local keyfiles_block
    keyfiles_block=$(printf 'The following keyFiles have been pre-loaded. Do NOT re-read these files:\n%s' "$inlined_files")
  else
    local keyfiles_block="(No keyFiles pre-loaded; use file discovery as needed.)"
  fi
  prompt=$(KEYFILES_BLOCK="$keyfiles_block" perl -0777 -pe \
    's/\Q{{INLINED_KEYFILES}}\E/$ENV{KEYFILES_BLOCK}/g' <<< "$prompt")

  printf '%s\n' "$prompt"
}

# Append a JSON line summarizing this iteration's cost signals to .ralph/cost.jsonl.
# Fields: timestamp, iteration, task_id, tier, model, initial_tokens, estimated_tokens,
# expansion_factor, duration_sec, outcome (task_complete|continued|stopped|error|complete).
log_iteration_cost() {
  local iteration="$1"
  local task_id="$2"
  local model="$3"
  local initial_tokens="$4"
  local estimated_tokens="$5"
  local expansion_factor="$6"
  local duration_sec="$7"
  local outcome="$8"

  local cost_log="$TARGET_REPO_ROOT/.ralph/cost.jsonl"
  local tier="unknown"
  if [ "$model" = "$OPENCODE_MODEL_STRONG" ]; then
    tier="strong"
  elif [ "$model" = "$OPENCODE_MODEL_CHEAP" ]; then
    tier="cheap"
  fi

  local ts
  ts=$(date --iso-8601=seconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Write a compact JSON line; no jq dependency here — hand-format
  printf '{"ts":"%s","iter":%d,"task":"%s","tier":"%s","model":"%s","initial_tokens":%d,"estimated_tokens":%d,"expansion":%d,"duration_sec":%d,"outcome":"%s"}\n' \
    "$ts" "$iteration" "$task_id" "$tier" "$model" "$initial_tokens" "$estimated_tokens" "$expansion_factor" "$duration_sec" "$outcome" \
    >> "$cost_log" 2>/dev/null || true
}

run_iteration() {
  local iteration="$1"
  local iter_start
  iter_start=$(date +%s)

  # Verify sidecars are alive before starting work
  check_sidecars

  # Truncate last-verify.log so only the current iteration's verify output
  # is retained. Prevents unbounded growth and stale grep hits from prior runs.
  if [ -f "$TARGET_REPO_ROOT/.ralph/last-verify.log" ]; then
    : > "$TARGET_REPO_ROOT/.ralph/last-verify.log"
  fi

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

  # Estimate prompt token count (rough: chars / 4)
  local prompt_chars initial_tokens key_files_count expansion_factor estimated_tokens
  prompt_chars=$(echo -n "$merged_prompt" | wc -c)
  initial_tokens=$((prompt_chars / 4))

  # Compute expansion factor based on task characteristics.
  # Base factor accounts for OpenCode's own system prompt (~4-8K) + expected
  # tool-call responses. Per-keyFile bonus accounts for file reads during
  # implementation. Test-heavy tasks expand more due to test iteration.
  key_files_count=0
  if [ -n "$SELECTED_TASK_JSON" ] && [ "$SELECTED_TASK_JSON" != "{}" ] && command -v jq >/dev/null 2>&1; then
    key_files_count=$(echo "$SELECTED_TASK_JSON" | jq '(.keyFiles // []) | length' 2>/dev/null || echo 0)
  fi
  expansion_factor=$((RALPH_CONTEXT_EXPANSION_BASE + key_files_count / 2))
  # Cap at 6x to avoid absurd upgrades on huge PRDs
  if [ "$expansion_factor" -gt 6 ]; then
    expansion_factor=6
  fi
  estimated_tokens=$((initial_tokens * expansion_factor))

  echo "[Ralph][context] Prompt: ${prompt_chars} chars ≈ ${initial_tokens} tokens; expansion ×${expansion_factor} (keyFiles=${key_files_count}) → est. runtime ${estimated_tokens} tokens" >&2

  local OUTPUT
  local is_retry="false"
  if [ "$SAME_TASK_COUNT" -gt 1 ]; then
    is_retry="true"
  fi
  local iteration_model
  iteration_model=$(resolve_iteration_model "$SELECTED_TASK_JSON" "$is_retry" "$estimated_tokens")

  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cd "$TARGET_REPO_ROOT" && printf "%s" "$merged_prompt" | amp --dangerously-allow-all 2>&1 | tee >(cat >&2)) || true
  elif [[ "$TOOL" == "claude" ]]; then
    OUTPUT=$(cd "$TARGET_REPO_ROOT" && printf "%s" "$merged_prompt" | claude --dangerously-skip-permissions --print 2>&1 | tee >(cat >&2)) || true
  else
    local model_flag=""
    if [[ -n "$iteration_model" ]]; then
      model_flag="--model $iteration_model"
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
    log_iteration_cost "$iteration" "$SELECTED_TASK_ID" "$iteration_model" "$initial_tokens" "$estimated_tokens" "$expansion_factor" "$elapsed" "complete"
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
    log_iteration_cost "$iteration" "$SELECTED_TASK_ID" "$iteration_model" "$initial_tokens" "$estimated_tokens" "$expansion_factor" "$elapsed" "stopped"
    echo "[Ralph][timer] iteration=$iteration duration=$(format_duration "$elapsed") total_elapsed=$(format_duration "$loop_elapsed")" >&2
    notify_and_exit 0 "Ralph: Stopped" "Agent requested stop at iteration $iteration of $MAX_ITERATIONS.\n<b>Iteration time:</b> $(format_duration "$elapsed")\n<b>Total time:</b> $(format_duration "$loop_elapsed")" 1
  fi

  # Unrecoverable error — the agent hit a fatal problem (permission denied,
  # missing credentials, broken environment, etc.) and emitted ERROR.
  if echo "$OUTPUT" | grep -q "<promise>ERROR</promise>"; then
    echo "" >&2
    echo "========================================" >&2
    echo "ERROR: Unrecoverable error at iteration $iteration." >&2
    # Extract the agent's error description (text after the ERROR tag)
    local error_msg
    error_msg=$(echo "$OUTPUT" | sed -n '/<promise>ERROR<\/promise>/,$ { /<promise>ERROR<\/promise>/d; p; }' | head -20)
    if [ -n "$error_msg" ]; then
      echo "$error_msg" >&2
    fi
    echo "========================================" >&2
    record_suggestions "$iteration" "error" "$OUTPUT"
    local iter_end elapsed loop_elapsed
    iter_end=$(date +%s)
    elapsed=$((iter_end - iter_start))
    loop_elapsed=$((iter_end - LOOP_START_SECS))
    log_iteration_cost "$iteration" "$SELECTED_TASK_ID" "$iteration_model" "$initial_tokens" "$estimated_tokens" "$expansion_factor" "$elapsed" "error"
    echo "[Ralph][timer] iteration=$iteration duration=$(format_duration "$elapsed") total_elapsed=$(format_duration "$loop_elapsed")" >&2
    notify_and_exit 1 "Ralph: Error" "Unrecoverable error at iteration $iteration. Check output for details." 1
  fi

  record_suggestions "$iteration" "continued" "$OUTPUT"

  # NuGet feed connectivity check. If the last verify log contains repeated
  # "Connection reset by peer" errors against nuget.org, the container likely
  # isn't seeing NUGET_PRIVATE_FEED_URL / PROGET_DOTNET_TOKEN. Warn loudly so
  # the user doesn't burn 20+ minutes per iteration on doomed restores.
  if [ -f "$TARGET_REPO_ROOT/.ralph/last-verify.log" ]; then
    local nuget_resets
    nuget_resets=$(grep -c "Connection reset by peer" "$TARGET_REPO_ROOT/.ralph/last-verify.log" 2>/dev/null || echo 0)
    if [ "${nuget_resets:-0}" -ge 3 ] 2>/dev/null; then
      echo "" >&2
      echo "[Ralph][WARN] Detected $nuget_resets NuGet 'Connection reset by peer' errors in this iteration." >&2
      echo "[Ralph][WARN] The container is likely hitting api.nuget.org instead of the private feed." >&2
      echo "[Ralph][WARN] Verify on host: env | grep -E 'NUGET_PRIVATE_FEED_URL|PROGET_DOTNET_TOKEN'" >&2
      echo "[Ralph][WARN] Also verify inside sidecar: docker exec \$RALPH_SIDECAR_DOTNET env | grep NUGET" >&2
      echo "[Ralph][WARN] If missing, stop stale sidecars: docker rm -f \$(docker ps -aq --filter name=ralph-sidecar-dotnet)" >&2
      echo "" >&2
    fi
  fi

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
  # Determine outcome for cost log.
  # An iteration counts as complete when EITHER the agent emitted
  # <promise>TASK_COMPLETE</promise> OR the task's passes field flipped to
  # true on disk. Agents sometimes finish the work but forget the promise
  # tag; treating that as completion gives accurate cost.jsonl telemetry.
  # (The task-selection query at line ~934 already skips passes:true tasks,
  # so this only affects logging, not loop behavior.)
  local iter_outcome="continued"
  if echo "$OUTPUT" | grep -q "<promise>TASK_COMPLETE</promise>"; then
    iter_outcome="task_complete"
  elif command -v jq >/dev/null 2>&1 && [ -f "$PRD_FILE" ] && [ -n "$SELECTED_TASK_ID" ]; then
    local outcome_passes
    outcome_passes=$(jq -r --arg id "$SELECTED_TASK_ID" \
      '(.tasks // [])[] | select(.id == $id) | .passes // false' "$PRD_FILE" 2>/dev/null || echo "false")
    if [ "$outcome_passes" = "true" ]; then
      iter_outcome="task_complete"
      echo "[Ralph] Task $SELECTED_TASK_ID passes:true on disk despite missing TASK_COMPLETE tag; counted as complete." >&2
    fi
  fi
  log_iteration_cost "$iteration" "$SELECTED_TASK_ID" "$iteration_model" "$initial_tokens" "$estimated_tokens" "$expansion_factor" "$elapsed" "$iter_outcome"
  echo "[Ralph][timer] iteration=$iteration duration=$(format_duration "$elapsed") total_elapsed=$(format_duration "$loop_elapsed")" >&2
  render_progress "$completed_tasks" "$remaining_tasks" "$loop_elapsed"
  echo "Iteration $iteration finished; continuing..."
}

# Pre-flight: verify the AI tool is reachable and permissions are correct.
# Only for opencode (amp/claude use --dangerously-* flags that bypass permissions).
preflight_tool_check() {
  if [ "$TOOL" != "opencode" ]; then
    return 0
  fi

  echo "[Ralph] Pre-flight: verifying OpenCode permissions..." >&2
  local model_flag=""
  if [[ -n "$OPENCODE_MODEL_CHEAP" ]]; then
    model_flag="--model $OPENCODE_MODEL_CHEAP"
  elif [[ -n "$OPENCODE_MODEL" ]]; then
    model_flag="--model $OPENCODE_MODEL"
  fi

  local probe_output
  probe_output=$(cd "$TARGET_REPO_ROOT" && printf "Reply with exactly: RALPH_OK" | timeout 60 opencode run $model_flag 2>&1) || true

  if echo "$probe_output" | grep -q "RALPH_OK"; then
    echo "[Ralph] Pre-flight passed." >&2
    return 0
  fi

  echo "" >&2
  echo "========================================" >&2
  echo "ERROR: OpenCode pre-flight check failed." >&2
  echo "The tool could not complete a trivial request." >&2
  echo "" >&2
  echo "Common causes:" >&2
  echo "  - Missing permissions in ~/.config/opencode/opencode.json" >&2
  echo "  - All tool permissions must be set to \"allow\"" >&2
  echo "  - external_directory must include your project path" >&2
  echo "  - Model/provider not configured or unreachable" >&2
  echo "" >&2
  echo "Probe output (last 10 lines):" >&2
  echo "$probe_output" | tail -10 >&2
  echo "========================================" >&2
  notify_and_exit 1 "Ralph: Pre-flight Failed" "OpenCode pre-flight check failed. Check permissions and model config." 1
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
  # Load private org overlay (cert URLs, private feeds) if present.
  # Silent no-op when absent so the public runner works out of the box.
  local private_env="$HOME/.config/ralph-private/org-values.env"
  if [ -f "$private_env" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$private_env"
    set +a
    local loaded_vars
    loaded_vars=$(grep -E '^[A-Z_]+=' "$private_env" 2>/dev/null | sed 's/#.*//' | grep -E '^[A-Z_]+=' | cut -d= -f1 | tr '\n' ' ')
    echo "[Ralph] Loaded private org overlay ($private_env): $loaded_vars" >&2
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
  # Auto-enable sidecar mode when Docker is available (opt-out via --no-sidecar)
  auto_enable_sidecar_mode
  # Launch sidecar containers (parallel start + background cache warming)
  launch_sidecars
  trap cleanup_sidecars EXIT
  # Verify the AI tool is reachable before burning full iterations
  preflight_tool_check
  run_iterations
}

main "$@"
