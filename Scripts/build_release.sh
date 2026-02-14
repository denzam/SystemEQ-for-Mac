#!/bin/bash
# Build Release version of SystemEQ for Mac for performance testing
# This creates an optimized build WITHOUT Xcode debugger overhead

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="SystemEQ for Mac"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"

echo "🚀 Building Release version of SystemEQ for Mac..."
echo "📁 Project: $PROJECT_DIR"
echo ""

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo "🧹 Cleaning previous build..."
    rm -rf "$BUILD_DIR"
fi

# Build Release configuration
echo "🔨 Building Release configuration..."
xcodebuild \
    -project "$PROJECT_DIR/SystemEQ for Mac.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=macOS" \
    build

# Find the built app
APP_PATH=$(find "$DERIVED_DATA" -name "SystemEQ for Mac.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Failed to find built app"
    exit 1
fi

# Copy to build directory
echo "📦 Copying app to build directory..."
mkdir -p "$BUILD_DIR"
cp -R "$APP_PATH" "$BUILD_DIR/"

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
