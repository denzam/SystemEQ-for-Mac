#!/bin/bash
# Build Release version of SystemEQ for Mac for performance testing
# This creates an optimized build WITHOUT Xcode debugger overhead

set -euo pipefail

if [[ $# -eq 1 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
    echo "Usage: $0"
    exit 0
fi
if [[ $# -ne 0 ]]; then
    echo "Unsupported arguments. Usage: $0" >&2
    exit 2
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="SystemEQ for Mac"
BUILD_DIR="$PROJECT_DIR/build"
TARGET_APP="$BUILD_DIR/$SCHEME.app"
STAGING_DIR=""
LOCK_OWNED=0
PUBLISHED=0

echo "🚀 Building Release version of SystemEQ for Mac..."
echo "📁 Project: $PROJECT_DIR"
echo ""

TEMP_DERIVED=$(mktemp -d "${TMPDIR:-/tmp}/systemeq-release.XXXXXX")
cleanup() {
    local status=$? failed=0 keep_staging=0
    trap - EXIT
    if [[ -n "$STAGING_DIR" && -e "$STAGING_DIR/previous.app" && "$PUBLISHED" == 0 ]]; then
        if [[ -e "$TARGET_APP" || -L "$TARGET_APP" ]]; then
            keep_staging=1
        elif ! mv "$STAGING_DIR/previous.app" "$TARGET_APP"; then
            keep_staging=1
            failed=1
        fi
        if [[ "$keep_staging" == 1 ]]; then
            echo "Previous build preserved at: $STAGING_DIR/previous.app" >&2
        fi
    fi
    if [[ -n "$STAGING_DIR" && "$keep_staging" == 0 ]]; then
        if ! rm -rf "$STAGING_DIR"; then failed=1; fi
    fi
    if ! rm -rf "$TEMP_DERIVED"; then failed=1; fi
    if [[ "$LOCK_OWNED" == 1 ]]; then
        if ! rmdir "$BUILD_DIR/.systemeq-release.lock"; then failed=1; fi
    fi
    if [[ "$status" == 0 && "$failed" == 1 ]]; then status=1; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Build Release configuration
echo "🔨 Building Release configuration..."
xcodebuild \
    -project "$PROJECT_DIR/SystemEQ for Mac.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$TEMP_DERIVED" \
    -destination "platform=macOS" \
    -quiet \
    build

# Find the built app
APP_PATH="$TEMP_DERIVED/Build/Products/Release/$SCHEME.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ Failed to find built app"
    exit 1
fi

echo "📦 Staging app to build directory..."
mkdir -p "$BUILD_DIR"
if ! mkdir "$BUILD_DIR/.systemeq-release.lock"; then
    echo "Release publication is locked; previous build was not changed." >&2
    exit 1
fi
LOCK_OWNED=1
if [[ -L "$TARGET_APP" ]]; then
    echo "Refusing to replace a symlinked app: $TARGET_APP" >&2
    exit 1
fi
STAGING_DIR=$(mktemp -d "$BUILD_DIR/.systemeq-release.XXXXXX")
cp -R "$APP_PATH" "$STAGING_DIR/$SCHEME.app"
if [[ -e "$TARGET_APP" ]]; then
    mv "$TARGET_APP" "$STAGING_DIR/previous.app"
fi
mv "$STAGING_DIR/$SCHEME.app" "$TARGET_APP"
PUBLISHED=1

echo ""
echo "✅ Release build complete!"
echo "📍 Location: $BUILD_DIR/SystemEQ for Mac.app"
echo ""
echo "To run:"
echo "  open \"$BUILD_DIR/SystemEQ for Mac.app\""
echo ""
echo "Performance comparison:"
echo "  Debug build (Xcode): ~100% CPU, 20-30 FPS"
echo "  Release build: ~30-40% CPU, 30 FPS (expected)"
