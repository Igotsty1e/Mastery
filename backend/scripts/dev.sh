#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BACKEND_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ENV_FILE="$BACKEND_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
  echo "[dev] env loaded from .env (AI_PROVIDER=${AI_PROVIDER:-stub})"
else
  echo "[dev] no .env found — using process environment (AI_PROVIDER=${AI_PROVIDER:-stub})"
fi

cd "$BACKEND_DIR"
exec npx tsx watch src/server.ts
