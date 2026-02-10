#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-mcr.microsoft.com/dotnet/sdk:8.0}"
CACHE_VOL="${CACHE_VOL:-ralph-cache}"

echo "[warm_caches] Using image: $IMAGE"
echo "[warm_caches] Cache volume: $CACHE_VOL"

docker volume create "$CACHE_VOL" >/dev/null

docker run --rm \
  -v "$CACHE_VOL:/cache" \
  "$IMAGE" \
  bash -lc "echo 'Cache volume ready at /cache'"

echo "[warm_caches] Done"
