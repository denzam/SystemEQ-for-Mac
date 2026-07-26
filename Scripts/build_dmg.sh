#!/bin/bash

# Build DMG for SystemEQ for Mac
# Creates a professional .dmg installer with drag-to-Applications layout
#
# Usage: ./Scripts/build_dmg.sh [version]
# Example: ./Scripts/build_dmg.sh 1.0.0

set -e

# Configuration
APP_NAME="SystemEQ for Mac"
SCHEME="SystemEQ for Mac"
PROJECT="SystemEQ for Mac.xcodeproj"
VERSION="${1:-1.0.0}"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_NAME="SystemEQ-v${VERSION}"
DMG_PATH="$BUILD_DIR/${DMG_NAME}.dmg"
DMG_TEMP="$BUILD_DIR/dmg_temp"

cd "$(dirname "$0")/.."

echo "═══════════════════════════════════════════════════════════════"
echo "  Building SystemEQ for Mac v${VERSION}"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Archive
echo "📦 [1/4] Archiving..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=YES \
    -quiet

echo "   ✅ Archive complete"

# Step 2: Export .app + ad-hoc sign
echo "📤 [2/4] Exporting and signing .app..."
mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_PATH/"

echo "   🔏 Ad-hoc signing (no Apple Developer account required)..."
codesign --deep --force --sign - "$EXPORT_PATH/$APP_NAME.app"
echo "   ✅ Export + sign complete"

# Step 3: Create DMG
echo "💿 [3/4] Creating DMG..."

# Create temporary DMG directory
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app
cp -R "$EXPORT_PATH/$APP_NAME.app" "$DMG_TEMP/"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP/Applications"

# Create background instructions file
cat > "$DMG_TEMP/.background_info" << INFO
Drag SystemEQ for Mac to Applications to install.
INFO

# Check if create-dmg is available (prettier DMG)
if command -v create-dmg &> /dev/null; then
    echo "   Using create-dmg for professional layout..."
    
    create-dmg \
        --volname "$APP_NAME" \
        --volicon "$EXPORT_PATH/$APP_NAME.app/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 200 \
        --icon "Applications" 450 200 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 450 200 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$DMG_TEMP" \
        2>/dev/null || {
        # Fallback to hdiutil if create-dmg fails
        echo "   Fallback to hdiutil..."
        hdiutil create -volname "$APP_NAME" \
            -srcfolder "$DMG_TEMP" \
            -ov -format UDZO \
            "$DMG_PATH"
    }
else
    echo "   Using hdiutil (install create-dmg for prettier DMG: brew install create-dmg)"
    
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo "   ✅ DMG created"

# Step 4: Cleanup
echo "🧹 [4/4] Cleanup..."
rm -rf "$DMG_TEMP"
rm -rf "$ARCHIVE_PATH"
rm -f "$BUILD_DIR/ExportOptions.plist"

# Get file size
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Build complete!"
echo ""
echo "  📁 DMG: $DMG_PATH"
echo "  📏 Size: $DMG_SIZE"
echo "  📋 Version: $VERSION"
echo ""
echo "  Next steps:"
echo "  1. Test the DMG by opening it"
echo "  2. Upload to GitHub Releases"
echo "  3. Tag: git tag v${VERSION} && git push --tags"
echo ""
echo "  ⚠️  Gatekeeper note (ad-hoc signed, no Developer ID):"
echo "  Users must right-click → Open on first launch, or run:"
echo "  xattr -rd com.apple.quarantine \"$APP_NAME.app\""
echo "═══════════════════════════════════════════════════════════════"
