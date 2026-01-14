#!/bin/bash
# Updates only the binary in /Applications/Recall.app
# Does NOT re-sign, preserving TCC accessibility authorization

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Building Recall (debug, no signing)..."
cd "$PROJECT_DIR"
swift build

echo "Updating binary in /Applications/Recall.app..."
cp "$PROJECT_DIR/.build/debug/Recall" "/Applications/Recall.app/Contents/MacOS/Recall"

# Remove signature to use the bundle's existing signature context
codesign --remove-signature "/Applications/Recall.app/Contents/MacOS/Recall" 2>/dev/null || true

echo "Done. Restart the app:"
echo "  pkill Recall; open /Applications/Recall.app"
