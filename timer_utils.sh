#!/usr/bin/env bash

# Timer and progress utilities for Ralph.

TOTAL_TASKS=0
LOOP_START_SECS=0

compute_total_tasks() {
  if ! command -v jq >/dev/null 2>&1; then
    TOTAL_TASKS=0
    return
  fi

  if [ ! -f "$PRD_FILE" ]; then
    TOTAL_TASKS=0
    return
  fi

  TOTAL_TASKS=$(jq '(.tasks // []) | length' "$PRD_FILE" 2>/dev/null || echo 0)
}

format_duration() {
  local seconds="$1"
  if [ -z "$seconds" ] || [ "$seconds" -lt 0 ]; then
    echo "0s"
    return
  fi
  local h m s
  h=$((seconds / 3600))
  m=$(((seconds % 3600) / 60))
  s=$((seconds % 60))
  if [ "$h" -gt 0 ]; then
    printf "%dh %02dm %02ds" "$h" "$m" "$s"
  elif [ "$m" -gt 0 ]; then
    printf "%dm %02ds" "$m" "$s"
  else
    printf "%ds" "$s"
  fi
}

render_progress() {
  local completed="$1"
  local remaining="$2"
  local elapsed_secs="$3"

  if [ -z "$TOTAL_TASKS" ] || [ "$TOTAL_TASKS" -le 0 ]; then
    return
  fi

  local total percent filled empty bar eta
  total="$TOTAL_TASKS"
  percent=$((completed * 100 / total))
  filled=$((percent / 5)) # 20-char bar
  empty=$((20 - filled))

  bar=""
  if [ "$filled" -gt 0 ]; then
    bar="$bar$(printf '%*s' "$filled" '' | tr ' ' '#')"
  fi
  if [ "$empty" -gt 0 ]; then
    bar="$bar$(printf '%*s' "$empty" '' | tr ' ' '.')"
  fi

  eta="n/a"
  if [ "$completed" -gt 0 ]; then
    local per_task
    per_task=$((elapsed_secs / completed))
    eta=$(format_duration $((per_task * remaining)))
  fi

  local elapsed_fmt
  elapsed_fmt=$(format_duration "$elapsed_secs")
  echo "[Ralph][progress] [$bar] ${percent}% (${completed}/${total}) elapsed=${elapsed_fmt} eta=${eta} remaining=${remaining}" >&2
}

compute_completed_tasks() {
  local total="$1"
  local remaining="$2"
  if [ -z "$total" ] || [ "$total" -le 0 ]; then
    echo 0
    return
  fi
  local completed
  completed=$((total - remaining))
  if [ "$completed" -lt 0 ]; then
    completed=0
  fi
  echo "$completed"
}
