#!/bin/bash

# Build DMG for SystemEQ for Mac
# Creates a professional .dmg installer with drag-to-Applications layout
#
# Usage: ./Scripts/build_dmg.sh [version]
# Example: ./Scripts/build_dmg.sh 1.0.0

set -euo pipefail

if [[ $# -eq 1 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
    echo "Usage: $0 [version]"
    exit 0
fi
if [[ $# -gt 1 || ! "${1:-1.0.0}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ ]]; then
    echo "Invalid version or arguments. Usage: $0 [version]" >&2
    exit 2
fi

# Configuration
APP_NAME="SystemEQ for Mac"
SCHEME="SystemEQ for Mac"
PROJECT="SystemEQ for Mac.xcodeproj"
VERSION="${1:-1.0.0}"
cd "$(dirname "$0")/.."
BUILD_DIR="build"
if [[ -L "$BUILD_DIR" ]]; then
    echo "Refusing a symlinked build directory." >&2
    exit 1
fi
mkdir -p "$BUILD_DIR"
LOCK_OWNED=0
STAGING_DIR=""
PUBLISHED=0
DMG_NAME="SystemEQ-v${VERSION}"
DMG_PATH="$BUILD_DIR/${DMG_NAME}.dmg"
cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$STAGING_DIR" && -e "$STAGING_DIR/previous.dmg" && "$PUBLISHED" == 0 ]]; then
        if [[ ! -e "$DMG_PATH" && ! -L "$DMG_PATH" ]]; then
            if ! mv "$STAGING_DIR/previous.dmg" "$DMG_PATH"; then status=1; fi
        fi
    fi
    if [[ "$LOCK_OWNED" == 1 ]]; then
        if ! rmdir "$BUILD_DIR/.systemeq-dmg.lock"; then status=1; fi
    fi
    if [[ -n "$STAGING_DIR" ]]; then
        echo "Build artifacts preserved at: $STAGING_DIR" >&2
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if ! mkdir "$BUILD_DIR/.systemeq-dmg.lock"; then
    echo "DMG build is locked; previous artifacts were not changed." >&2
    exit 1
fi
LOCK_OWNED=1
if [[ -L "$DMG_PATH" ]]; then
    echo "Refusing to replace a symlinked DMG." >&2
    exit 1
fi
STAGING_DIR=$(mktemp -d "$BUILD_DIR/.systemeq-dmg.XXXXXX")
ARCHIVE_PATH="$STAGING_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$STAGING_DIR/export"
STAGED_DMG_PATH="$STAGING_DIR/${DMG_NAME}.dmg"
DMG_TEMP="$STAGING_DIR/dmg_temp"

echo "═══════════════════════════════════════════════════════════════"
echo "  Building SystemEQ for Mac v${VERSION}"
echo "═══════════════════════════════════════════════════════════════"
echo ""

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
codesign --verify --deep --strict "$EXPORT_PATH/$APP_NAME.app"
echo "   ✅ Export + sign complete"

# Step 3: Create DMG
echo "💿 [3/4] Creating DMG..."

# Create temporary DMG directory
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
    
    if ! create-dmg \
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
        "$STAGED_DMG_PATH" \
        "$DMG_TEMP"; then
        # Fallback to hdiutil if create-dmg fails
        echo "   ⚠️ create-dmg failed; falling back to hdiutil..." >&2
        hdiutil create -volname "$APP_NAME" \
            -srcfolder "$DMG_TEMP" \
            -ov -format UDZO \
            "$STAGED_DMG_PATH"
    fi
else
    echo "   Using hdiutil (install create-dmg for prettier DMG: brew install create-dmg)"
    
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$STAGED_DMG_PATH"
fi

echo "   ✅ DMG created"

hdiutil verify "$STAGED_DMG_PATH"
test -s "$STAGED_DMG_PATH"
if [[ -e "$DMG_PATH" ]]; then
    mv "$DMG_PATH" "$STAGING_DIR/previous.dmg"
fi
mv "$STAGED_DMG_PATH" "$DMG_PATH"
PUBLISHED=1

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
