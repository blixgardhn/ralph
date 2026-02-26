#!/usr/bin/env bash
set -euo pipefail

FAST=${VERIFY_FAST:-false}
ENGINE=${CONTAINER_ENGINE:-docker}
NODE_IMAGE=${VERIFY_NODE_IMAGE:-node:20-alpine}
DOTNET_IMAGE=${VERIFY_DOTNET_IMAGE:-mcr.microsoft.com/dotnet/sdk:8.0}
NODE_SERVICE=${VERIFY_NODE_SERVICE:-}
DOTNET_SERVICE=${VERIFY_DOTNET_SERVICE:-}

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

ensure_engine() {
  if ! command -v "$ENGINE" >/dev/null 2>&1; then
    echo "[verify] Container engine '$ENGINE' not found. Install docker or podman and set CONTAINER_ENGINE if needed." >&2
    exit 1
  fi
}

have_compose() {
  if [ ! -f docker-compose.yml ] && [ ! -f compose.yml ]; then
    return 1
  fi
  "$ENGINE" compose version >/dev/null 2>&1
}

run_in_container() {
  local service="$1"
  local image="$2"
  local cmd="$3"

  if have_compose && [ -n "$service" ]; then
    "$ENGINE" compose run --rm "$service" bash -lc "$cmd"
    return
  fi

  "$ENGINE" run --rm -v "$PWD:/work" -w /work "$image" bash -lc "$cmd"
}

node_fast() {
  run_step "npm test (fast, containerized)" run_in_container "$NODE_SERVICE" "$NODE_IMAGE" "npm test -- --runInBand"
}

node_full() {
  run_step "npm ci (containerized)" run_in_container "$NODE_SERVICE" "$NODE_IMAGE" "npm ci"
  run_step "npm test (containerized)" run_in_container "$NODE_SERVICE" "$NODE_IMAGE" "npm test"
}

dotnet_fast() {
  run_step "dotnet test (fast, containerized)" run_in_container "$DOTNET_SERVICE" "$DOTNET_IMAGE" "dotnet test --no-build"
}

dotnet_full() {
  run_step "dotnet restore (containerized)" run_in_container "$DOTNET_SERVICE" "$DOTNET_IMAGE" "dotnet restore"
  run_step "dotnet format (containerized)" run_in_container "$DOTNET_SERVICE" "$DOTNET_IMAGE" "dotnet format --verify-no-changes"
  run_step "dotnet test (containerized)" run_in_container "$DOTNET_SERVICE" "$DOTNET_IMAGE" "dotnet test"
}

main() {
  ensure_engine

  if [[ "$FAST" == "true" ]]; then
    if [ -f package.json ]; then
      node_fast
    elif compgen -G "*.sln" >/dev/null; then
      dotnet_fast
    else
      banner "No fast verify steps configured"
    fi
  else
    if [ -f package.json ]; then
      node_full
    elif compgen -G "*.sln" >/dev/null; then
      dotnet_full
    else
      banner "No verify steps configured"
    fi
  fi

  echo "verify.sh complete"
}

main "$@"
