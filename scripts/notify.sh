#!/bin/bash
# Pushover notification helper for Ralph.
# Usage: scripts/notify.sh <title> <message> [priority]
#
# Requires environment variables:
#   PUSHOVER_TOKEN    - Pushover application API token
#   PUSHOVER_USER_KEY - Pushover user key
#
# Optional:
#   PUSHOVER_DEVICE   - Target specific device (default: all devices)
#   PUSHOVER_SOUND    - Notification sound (default: pushover)
#
# Priority levels:
#   -2  lowest (no notification)
#   -1  low (quiet)
#    0  normal (default)
#    1  high (bypasses quiet hours)
#    2  emergency (requires acknowledgment; uses 30s retry, 300s expire)

set -euo pipefail

TITLE="${1:-Ralph Notification}"
MESSAGE="${2:-No message provided}"
PRIORITY="${3:-0}"

if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER_KEY:-}" ]; then
  echo "[Ralph][notify] Skipping notification: PUSHOVER_TOKEN or PUSHOVER_USER_KEY not set." >&2
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "[Ralph][notify] Skipping notification: curl not installed." >&2
  exit 0
fi

# Build the curl args
CURL_ARGS=(
  -s
  --form-string "token=$PUSHOVER_TOKEN"
  --form-string "user=$PUSHOVER_USER_KEY"
  --form-string "title=$TITLE"
  --form-string "message=$MESSAGE"
  --form-string "priority=$PRIORITY"
  --form-string "html=1"
)

if [ -n "${PUSHOVER_DEVICE:-}" ]; then
  CURL_ARGS+=(--form-string "device=$PUSHOVER_DEVICE")
fi

if [ -n "${PUSHOVER_SOUND:-}" ]; then
  CURL_ARGS+=(--form-string "sound=$PUSHOVER_SOUND")
fi

# Emergency priority requires retry and expire
if [ "$PRIORITY" = "2" ]; then
  CURL_ARGS+=(--form-string "retry=30" --form-string "expire=300")
fi

RESPONSE=$(curl "${CURL_ARGS[@]}" https://api.pushover.net/1/messages.json 2>&1) || true

if echo "$RESPONSE" | grep -q '"status":1'; then
  echo "[Ralph][notify] Notification sent: $TITLE" >&2
else
  echo "[Ralph][notify] Notification may have failed. Response: $RESPONSE" >&2
fi
