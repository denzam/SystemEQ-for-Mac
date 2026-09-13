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
BACKUP_RETENTION_COUNT=3
mkdir -p "$LOG_DIR"

prune_install_backups() {
    local -a backups=()
    local -a ordered_backups=()
    local backup path remove_count index

    while IFS= read -r -d '' path; do
        if [[ -d "$path/original.app" && ! -L "$path/original.app" && -f "$path/original.app/Contents/Info.plist" ]]; then
            backups+=("$path")
        fi
    done < <(find "$LOG_DIR" -mindepth 1 -maxdepth 1 -type d -name 'previous.*' -print0)

    if (( ${#backups[@]} <= BACKUP_RETENTION_COUNT )); then return; fi

    while IFS=$'\t' read -r _ path; do
        ordered_backups+=("$path")
    done < <(
        for backup in "${backups[@]}"; do
            printf '%s\t%s\n' "$(/usr/bin/stat -f '%Fm' "$backup")" "$backup"
        done | /usr/bin/sort -n
    )

    remove_count=$((${#ordered_backups[@]} - BACKUP_RETENTION_COUNT))
    for ((index = 0; index < remove_count; index++)); do
        path="${ordered_backups[index]}"
        if [[ "$path" == "$LOG_DIR"/previous.* && -d "$path" && ! -L "$path" ]]; then
            if ! rm -rf "$path"; then
                echo "Warning: failed to remove old backup: $path" >&2
            fi
        fi
    done
}

cleanup_install_staging() {
    local path="${STAGING_DIR:-}"
    if [[ "$path" == /Applications/.SystemEQ-update.* && -d "$path" && ! -L "$path" ]]; then
        if ! rm -rf "$path"; then
            echo "Warning: failed to remove install staging directory: $path" >&2
        fi
    fi
}

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
    [[ ! -e "$INSTALLED_APP" || -d "$INSTALLED_APP" ]] || {
        echo "Refusing to replace a non-directory app path." >&2
        exit 1
    }
    STAGING_DIR="$(mktemp -d '/Applications/.SystemEQ-update.XXXXXX')"
    trap cleanup_install_staging EXIT
    /usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
    /usr/bin/codesign --verify --deep --strict "$STAGING_DIR/$APP_NAME.app"
    BACKUP_DIR=""
    if [[ -e "$INSTALLED_APP" ]]; then
        BACKUP_DIR="$(mktemp -d "$LOG_DIR/previous.XXXXXX")"
        if ! /usr/bin/ditto "$INSTALLED_APP" "$BACKUP_DIR/original.app" || \
            ! diff -qr "$INSTALLED_APP" "$BACKUP_DIR/original.app" >/dev/null; then
            rm -rf "$BACKUP_DIR"
            exit 1
        fi
        mv "$INSTALLED_APP" "$STAGING_DIR/previous.app"
    fi
    if ! mv "$STAGING_DIR/$APP_NAME.app" "$INSTALLED_APP"; then
        if [[ -d "$STAGING_DIR/previous.app" ]]; then
            if mv "$STAGING_DIR/previous.app" "$INSTALLED_APP"; then
                if [[ -n "$BACKUP_DIR" ]] && ! rm -rf "$BACKUP_DIR"; then
                    echo "Warning: failed to remove backup from the aborted install: $BACKUP_DIR" >&2
                fi
            else
                echo "Install and rollback failed; verified backup: $BACKUP_DIR/original.app" >&2
            fi
        fi
        exit 1
    fi
    if [[ -d "$STAGING_DIR/previous.app" ]]; then
        rm -rf "$STAGING_DIR/previous.app"
    fi
    cleanup_install_staging
    STAGING_DIR=""
    trap - EXIT
    prune_install_backups
    APP_BUNDLE="$INSTALLED_APP"
    if [[ -n "$BACKUP_DIR" ]]; then echo "Previous version: $BACKUP_DIR"; fi
fi

/usr/bin/open -n "$APP_BUNDLE"
if [[ "$MODE" == "--verify" || "$MODE" == "--install" ]]; then
    sleep 2
    pgrep -x "$APP_NAME"
fi
