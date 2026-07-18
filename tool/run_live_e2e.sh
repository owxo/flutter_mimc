#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
DEVICE="${1:-macos}"

: "${MIMC_TOKEN_ENDPOINT:?MIMC_TOKEN_ENDPOINT is required}"
: "${MIMC_APP_ID:?MIMC_APP_ID is required}"
if [[ -z "${FASTADMIN_USER_TOKEN:-}" && -z "${MIMC_TEST_AUTH_TOKEN:-}" ]]; then
  echo 'FASTADMIN_USER_TOKEN or MIMC_TEST_AUTH_TOKEN is required' >&2
  exit 1
fi

ACCOUNT="${MIMC_ACCOUNT:-mimc_e2e_a}"
PEER_ACCOUNT="${MIMC_PEER_ACCOUNT:-mimc_e2e_b}"
PEER_RESOURCE="${MIMC_PEER_RESOURCE:-}"
RESOURCE="${MIMC_RESOURCE:-$DEVICE}"

ARGS=(
  test integration_test/live_mimc_integration_test.dart
  -d "$DEVICE"
  --dart-define=MIMC_LIVE_TEST=true
  --dart-define=MIMC_APP_ID="$MIMC_APP_ID"
  --dart-define=MIMC_ACCOUNT="$ACCOUNT"
  --dart-define=MIMC_PEER_ACCOUNT="$PEER_ACCOUNT"
  --dart-define=MIMC_PEER_RESOURCE="$PEER_RESOURCE"
  --dart-define=MIMC_RESOURCE="$RESOURCE"
  --dart-define=MIMC_TOKEN_ENDPOINT="$MIMC_TOKEN_ENDPOINT"
  --dart-define=FASTADMIN_USER_TOKEN="${FASTADMIN_USER_TOKEN:-}"
  --dart-define=MIMC_TEST_AUTH_TOKEN="${MIMC_TEST_AUTH_TOKEN:-}"
)

if [[ "${MIMC_LIVE_RTS_TEST:-false}" == "true" ]]; then
  ARGS+=(--dart-define=MIMC_LIVE_RTS_TEST=true)
fi

if [[ "${MIMC_LIVE_RTS_RECEIVER_TEST:-false}" == "true" ]]; then
  ARGS+=(--dart-define=MIMC_LIVE_RTS_RECEIVER_TEST=true)
fi

cd "$ROOT_DIR/example"

if [[ "$DEVICE" == "chrome" ]]; then
  LOG_FILE="$(mktemp -t flutter_mimc_web_e2e.XXXXXX)"
  cleanup() {
    if [[ -n "${RUN_PID:-}" ]]; then
      kill -INT "$RUN_PID" 2>/dev/null || true
      wait "$RUN_PID" 2>/dev/null || true
    fi
    rm -f "$LOG_FILE"
  }
  trap cleanup EXIT INT TERM

  "$FLUTTER_BIN" run -d chrome --web-port 7357 \
    --dart-define=MIMC_AUTO_START=true \
    --dart-define=MIMC_APP_ID="$MIMC_APP_ID" \
    --dart-define=MIMC_ACCOUNT="$ACCOUNT" \
    --dart-define=MIMC_PEER_ACCOUNT="$PEER_ACCOUNT" \
    --dart-define=MIMC_PEER_RESOURCE="$PEER_RESOURCE" \
    --dart-define=MIMC_RESOURCE="$RESOURCE" \
    --dart-define=MIMC_TOKEN_ENDPOINT="$MIMC_TOKEN_ENDPOINT" \
    --dart-define=FASTADMIN_USER_TOKEN="${FASTADMIN_USER_TOKEN:-}" \
    --dart-define=MIMC_TEST_AUTH_TOKEN="${MIMC_TEST_AUTH_TOKEN:-}" \
    > >(tee "$LOG_FILE") 2>&1 &
  RUN_PID=$!

  for _ in {1..90}; do
    if grep -q 'MIMC_LIVE_E2E_PASS' "$LOG_FILE"; then
      echo 'Web MIMC live E2E passed.'
      exit 0
    fi
    if grep -q '\[flutter_mimc\].*failed:' "$LOG_FILE"; then
      echo 'Web MIMC live E2E failed.' >&2
      exit 1
    fi
    if ! kill -0 "$RUN_PID" 2>/dev/null; then
      wait "$RUN_PID"
      exit $?
    fi
    sleep 1
  done
  echo 'Web MIMC live E2E timed out.' >&2
  exit 1
fi

exec "$FLUTTER_BIN" "${ARGS[@]}"
