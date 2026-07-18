#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PHP_ROOT="$ROOT_DIR/example/backend/php"
ENV_FILE="${MIMC_ENV_FILE:-$PHP_ROOT/.env}"

if ! command -v php >/dev/null 2>&1; then
  echo "php was not found; install PHP 8.1 or newer" >&2
  exit 1
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

: "${MIMC_APP_ID:?MIMC_APP_ID is required}"
: "${MIMC_APP_KEY:?MIMC_APP_KEY is required}"
: "${MIMC_APP_SECRET:?MIMC_APP_SECRET is required}"

exec php -S "${MIMC_PHP_LISTEN:-0.0.0.0:8787}" -t "$PHP_ROOT/public"
