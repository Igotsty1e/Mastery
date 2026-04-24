#!/usr/bin/env bash
# Build and archive the Flutter iOS app for TestFlight.
# Prerequisites: Xcode (full), CocoaPods, Apple Developer account, valid signing cert.
# Usage: ./scripts/build-ios.sh [--upload]
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../app" && pwd)"
ARCHIVE_PATH="$APP_DIR/build/ios/Runner.xcarchive"
EXPORT_PATH="$APP_DIR/build/ios/export"

cd "$APP_DIR"

echo "==> flutter build ios (release)"
flutter build ios --release --no-codesign

echo "==> xcodebuild archive"
xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -sdk iphoneos \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

if [[ "${1:-}" == "--upload" ]]; then
  echo "==> xcodebuild export + upload to App Store Connect"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist ios/ExportOptions.plist
  echo "==> Upload complete — check TestFlight in App Store Connect"
else
  echo "==> Archive ready at $ARCHIVE_PATH"
  echo "==> Re-run with --upload to export and push to TestFlight"
fi
