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

if [ "${REQUIRE_API_BASE_URL:-}" = "true" ] && [ -z "${API_BASE_URL:-}" ]; then
  echo "[render-build] API_BASE_URL is required when REQUIRE_API_BASE_URL=true" >&2
  exit 1
fi

# ── Install Flutter (cached) ──────────────────────────────────────────────
# Render's incremental-cache layer can restore a partial Flutter SDK where
# `bin/flutter` exists but the `packages/flutter_tools/` directory doesn't.
# In that state every build fails with "Unable to 'pub upgrade' flutter tool"
# x10 retries because shared.sh tries to cd into the missing directory.
# Treat any missing critical sub-path as cache corruption and re-extract
# from scratch.
flutter_sdk_intact() {
  [ -x "$FLUTTER_DIR/bin/flutter" ] \
    && [ -d "$FLUTTER_DIR/packages/flutter_tools" ] \
    && [ -d "$FLUTTER_DIR/bin/cache" ] \
    && [ -f "$FLUTTER_DIR/version" ]
}

if ! flutter_sdk_intact; then
  if [ -d "$FLUTTER_DIR" ]; then
    echo "[render-build] Cached Flutter at $FLUTTER_DIR is corrupted (missing packages/flutter_tools or bin/cache). Re-extracting."
    rm -rf "$FLUTTER_DIR"
  else
    echo "[render-build] Installing Flutter $FLUTTER_VERSION → $FLUTTER_DIR"
  fi
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
# API_BASE_URL should be set explicitly in deployment.
# Local fallback stays on localhost so the script does not bake a
# private production endpoint into committed source.
BACKEND_URL="${API_BASE_URL:-http://localhost:3000}"
echo "[render-build] Building Flutter web → API_BASE_URL=$BACKEND_URL"

cd app

# Mirror backend's generated audio + image assets into the Flutter web bundle
# so the frontend serves them from its own origin. Same-origin loads dodge
# canvaskit's cross-origin canvas-tainting issue and the variable-font
# breakage of the html renderer simultaneously. Mobile / desktop targets
# still use the backend URL (see AppConfig.apiBaseUrl + the kIsWeb branch in
# the widgets).
mkdir -p web/audio web/images
if [ -d ../backend/public/audio ]; then
  cp -R ../backend/public/audio/. web/audio/
fi
if [ -d ../backend/public/images ]; then
  cp -R ../backend/public/images/. web/images/
fi

# Wave 7.4 part 2B: enable the auth surface in production builds. Sign-in
# screen runs before onboarding when the device has no refresh token; the
# learner state facades point at the auth-protected /me/skills/... and
# /me/reviews/due endpoints once a session exists. Skip-for-now keeps the
# original device-scoped flow.
flutter pub get
flutter build web \
  --dart-define=API_BASE_URL="$BACKEND_URL" \
  --dart-define=MASTERY_AUTH_ENABLED=true \
  --release

echo "[render-build] Done. Output: app/build/web"
