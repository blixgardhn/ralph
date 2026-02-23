#!/usr/bin/env bash
set -euo pipefail

FAST=${VERIFY_FAST:-false}

banner() {
  echo "========== $* =========="
}

run_step() {
  local label="$1"; shift
  local start end
  start=$(date +%s)
  banner "$label"
  "$@"
  end=$(date +%s)
  echo "[timing] $label: $((end - start))s"
}

if [[ "$FAST" == "true" ]]; then
  # Minimal checks for iteration speed; extend per stack as needed.
  if [ -f package.json ]; then
    run_step "npm test --runInBand (fast)" bash -lc "npm test -- --runInBand"
  elif compgen -G "*.sln" >/dev/null; then
    run_step "dotnet test (fast)" dotnet test --no-build
  else
    banner "No fast verify steps configured"
  fi
else
  # Full suite placeholder; projects should extend.
  if [ -f package.json ]; then
    run_step "npm install" npm install
    run_step "npm test" npm test
  elif compgen -G "*.sln" >/dev/null; then
    run_step "dotnet restore" dotnet restore
    run_step "dotnet format" dotnet format --verify-no-changes
    run_step "dotnet test" dotnet test
  else
    banner "No verify steps configured"
  fi
fi

echo "verify.sh complete"
