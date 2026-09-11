#!/bin/bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
    run|--build-only|--install|--verify) ;;
    *) echo "Usage: $0 [--build-only|--install|--verify]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData/EQProcessorMove"
APP_NAME="SystemEQ for Mac"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"
LOG_DIR="$ROOT_DIR/LocalArtifacts/LocalRun"
mkdir -p "$LOG_DIR"

stop_app() {
    if pgrep -x "$APP_NAME" >/dev/null; then
        /usr/bin/osascript -e 'tell application id "com.denzam.SystemEQ" to quit'
        for ((attempt = 0; attempt < 50; attempt++)); do
            if ! pgrep -x "$APP_NAME" >/dev/null; then return; fi
            sleep 0.1
        done
        echo "SystemEQ did not quit; no app bundle was replaced." >&2
        exit 1
    fi
}

if [[ "$MODE" != "--build-only" ]]; then stop_app; fi

if ! xcodebuild -project "$ROOT_DIR/SystemEQ for Mac.xcodeproj" \
    -scheme "$APP_NAME" -configuration Release \
    -destination "platform=macOS,arch=arm64" -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    build >"$LOG_DIR/build.log" 2>&1; then
    tail -60 "$LOG_DIR/build.log" >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
echo "Release build: $APP_BUNDLE"
if [[ "$MODE" == "--build-only" ]]; then exit 0; fi

if [[ "$MODE" == "--install" ]]; then
    [[ ! -L "$INSTALLED_APP" ]] || { echo "Refusing to replace a symlink." >&2; exit 1; }
    STAGING_DIR="$(mktemp -d '/Applications/.SystemEQ-update.XXXXXX')"
    /usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
    /usr/bin/codesign --verify --deep --strict "$STAGING_DIR/$APP_NAME.app"
    BACKUP_DIR="$(mktemp -d "$LOG_DIR/previous.XXXXXX")"
    if [[ -e "$INSTALLED_APP" ]]; then
        /usr/bin/ditto "$INSTALLED_APP" "$BACKUP_DIR/$APP_NAME.app"
        diff -qr "$INSTALLED_APP" "$BACKUP_DIR/$APP_NAME.app" >/dev/null
        mv "$INSTALLED_APP" "$STAGING_DIR/previous.app"
    fi
    if ! mv "$STAGING_DIR/$APP_NAME.app" "$INSTALLED_APP"; then
        if [[ -d "$STAGING_DIR/previous.app" ]]; then
            mv "$STAGING_DIR/previous.app" "$INSTALLED_APP"
        fi
        exit 1
    fi
    if [[ -d "$STAGING_DIR/previous.app" ]]; then
        mv "$STAGING_DIR/previous.app" "$BACKUP_DIR/original.app"
    fi
    rmdir "$STAGING_DIR"
    APP_BUNDLE="$INSTALLED_APP"
    echo "Previous version: $BACKUP_DIR"
fi

/usr/bin/open -n "$APP_BUNDLE"
if [[ "$MODE" == "--verify" || "$MODE" == "--install" ]]; then
    sleep 2
    pgrep -x "$APP_NAME"
fi
