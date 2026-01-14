#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Recall"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."

# Build release binary
cd "$PROJECT_DIR"
swift build -c release

# Create app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/release/Recall" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Code sign (ad-hoc for local use, or with identity for distribution)
if [ -n "$CODESIGN_IDENTITY" ]; then
    echo "Signing with identity: $CODESIGN_IDENTITY"
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "Ad-hoc signing..."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo ""
echo "Build complete: $APP_BUNDLE"
echo ""
echo "To install, copy to /Applications:"
echo "  cp -r \"$APP_BUNDLE\" /Applications/"
echo ""
echo "For distribution, set CODESIGN_IDENTITY and run again."
