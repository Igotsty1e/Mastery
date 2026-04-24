#!/usr/bin/env bash
# Build Flutter web for Render Static Site.
# Called by render.yaml buildCommand from the repo root.
# Caches the Flutter SDK in RENDER_CACHE_DIR when available.
set -euo pipefail

FLUTTER_VERSION="3.22.2"
CACHE_DIR="${RENDER_CACHE_DIR:-$HOME/.cache/render}"
FLUTTER_DIR="$CACHE_DIR/flutter-$FLUTTER_VERSION"
FLUTTER_ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_ARCHIVE}"

# ── Install Flutter (cached) ──────────────────────────────────────────────
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "[render-build] Installing Flutter $FLUTTER_VERSION → $FLUTTER_DIR"
  mkdir -p "$CACHE_DIR"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "$FLUTTER_URL" -o "$TMP/$FLUTTER_ARCHIVE"
  tar xJ -C "$TMP" -f "$TMP/$FLUTTER_ARCHIVE"
  mv "$TMP/flutter" "$FLUTTER_DIR"
else
  echo "[render-build] Using cached Flutter $FLUTTER_VERSION"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
flutter --version
flutter config --no-analytics

# ── Build ─────────────────────────────────────────────────────────────────
# API_BASE_URL is set as a Render build-time env var (see render.yaml).
# Default falls back to the free-tier backend slug.
BACKEND_URL="${API_BASE_URL:-https://mastery-backend.onrender.com}"
echo "[render-build] Building Flutter web → API_BASE_URL=$BACKEND_URL"

cd app
flutter pub get
flutter build web \
  --dart-define=API_BASE_URL="$BACKEND_URL" \
  --release

echo "[render-build] Done. Output: app/build/web"
