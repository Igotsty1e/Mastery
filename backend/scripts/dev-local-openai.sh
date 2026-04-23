#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BACKEND_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ENV_FILE="$BACKEND_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "OPENAI_API_KEY is empty in $ENV_FILE" >&2
  exit 1
fi

cd "$BACKEND_DIR"
exec npx tsx watch src/server.ts
