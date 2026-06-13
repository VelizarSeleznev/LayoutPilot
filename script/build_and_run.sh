#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PROJECT_NAME="LayoutPilot"
SCHEME="LayoutPilot"
PROJECT_FILE="LayoutPilot.xcodeproj"
DERIVED_DATA=".build"
APP_NAME="LayoutPilot"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
APP_ID="com.velizard.LayoutPilot"
INSTALL_DIR="${LAYOUTPILOT_INSTALL_DIR:-/Applications}"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
INSTALLED_APP_BINARY="$INSTALLED_APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required before building LayoutPilot." >&2
  exit 1
fi

xcodegen

xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

install_app() {
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALLED_APP_BUNDLE"
  /usr/bin/ditto "$APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$INSTALLED_APP_BUNDLE"
}

open_app() {
  install_app
  /usr/bin/open -n "$INSTALLED_APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  install)
    install_app
    ;;
  --debug|debug)
    install_app
    lldb -- "$INSTALLED_APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$APP_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|install|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
