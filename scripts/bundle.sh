#!/bin/bash
# Build Tidy.app bundle from SPM release binary
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$PROJECT_DIR/build/Tidy.app"

echo "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/Tidy" "$APP_DIR/Contents/MacOS/Tidy"

# Copy Info.plist
cp "$PROJECT_DIR/bundle/Info.plist" "$APP_DIR/Contents/Info.plist"

# Sign with ad-hoc signature (needed for local execution)
codesign --force --sign - "$APP_DIR"

echo ""
echo "Built: $APP_DIR"
echo ""
echo "To install:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "To run:"
echo "  open $APP_DIR"
