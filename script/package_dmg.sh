#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="LayoutPilot"
SCHEME="LayoutPilot"
PROJECT_FILE="LayoutPilot.xcodeproj"
DERIVED_DATA=".build"
DMG_NAME="LayoutPilot.dmg"
DMG_VOLNAME="LayoutPilot"
REQUIRED_DISTRIBUTION_SIGNING="${REQUIRED_DISTRIBUTION_SIGNING:-0}"

DMG_STAGE=""
DMG_MOUNT=""
BUILD_SETTINGS=()

cleanup() {
  if [ -n "$DMG_MOUNT" ] && mount | grep -q "on $DMG_MOUNT "; then
    hdiutil detach "$DMG_MOUNT" >/dev/null || true
  fi

  if [ -n "$DMG_STAGE" ]; then
    rm -rf "$DMG_STAGE"
  fi
}

trap cleanup EXIT

if [ "$REQUIRED_DISTRIBUTION_SIGNING" = "1" ]; then
  DEVELOPER_ID_IDENTITY="$(security find-identity -p codesigning -v | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"

  if [ -z "$DEVELOPER_ID_IDENTITY" ]; then
    echo "Error: Developer ID Application signing identity is required for a distributable DMG." >&2
    echo "Install the Developer ID Application certificate, then rerun:" >&2
    echo "  REQUIRED_DISTRIBUTION_SIGNING=1 ./script/package_dmg.sh" >&2
    exit 1
  fi

  BUILD_SETTINGS=(
    "CODE_SIGN_IDENTITY=$DEVELOPER_ID_IDENTITY"
    "ENABLE_HARDENED_RUNTIME=YES"
  )
elif ! security find-identity -p codesigning -v | grep -q 'Developer ID Application'; then
  echo "Warning: no Developer ID Application identity found; this DMG is development-signed only." >&2
  echo "         It may not open normally on another user's Mac." >&2
fi

echo "=== Step 1: Regenerating project with xcodegen ==="
xcodegen

echo "=== Step 2: Building in Release configuration ==="
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  clean build \
  "${BUILD_SETTINGS[@]}"

RELEASE_DIR="$DERIVED_DATA/Build/Products/Release"
APP_PATH="$RELEASE_DIR/$PROJECT_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: Release build succeeded, but app bundle not found at $APP_PATH" >&2
  exit 1
fi

echo "=== Step 3: Verifying Release app signature ==="
codesign --verify --deep --strict --verbose=4 "$APP_PATH"

echo "=== Step 4: Preparing DMG staging directory ==="
DMG_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/layoutpilot-dmg-stage.XXXXXX")"

echo "=== Step 5: Copying app bundle ==="
ditto --noqtn "$APP_PATH" "$DMG_STAGE/$PROJECT_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"

echo "=== Step 6: Verifying staged app signature ==="
codesign --verify --deep --strict --verbose=4 "$DMG_STAGE/$PROJECT_NAME.app"

echo "=== Step 7: Creating DMG ==="
rm -f "$DMG_NAME"
hdiutil create \
  -volname "$DMG_VOLNAME" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_NAME"

echo "=== Step 8: Verifying DMG contents ==="
DMG_MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/layoutpilot-dmg-mount.XXXXXX")"
hdiutil attach -nobrowse -readonly -mountpoint "$DMG_MOUNT" "$DMG_NAME" >/dev/null
codesign --verify --deep --strict --verbose=4 "$DMG_MOUNT/$PROJECT_NAME.app"
hdiutil detach "$DMG_MOUNT" >/dev/null
DMG_MOUNT=""

echo "=== Step 9: Inspecting DMG image ==="
hdiutil verify "$DMG_NAME"

echo "=== Success! DMG created at $DMG_NAME ==="
