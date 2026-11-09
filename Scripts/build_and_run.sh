#!/bin/bash
set -euo pipefail

MODE=""
SIGN_STYLE="developer-id"
IDENTITY_ARG=""
TEAM_ID_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo "Usage: $0 [run|--build-only|--install|--verify] [OPTIONS]"
            echo ""
            echo "Modes:"
            echo "  run                Build, sign, and launch SystemEQ (default)"
            echo "  --build-only       Build and verify without installing or launching"
            echo "  --install          Build, sign, install to /Applications, and launch"
            echo "  --verify           Build, sign, launch, and verify running process"
            echo ""
            echo "Options:"
            echo "  --ad-hoc           Use ad-hoc signing (only permitted with --build-only)"
            echo "  --identity <id>    Code signing identity (or SYSTEMEQ_SIGN_IDENTITY / CODE_SIGN_IDENTITY)"
            echo "  --team-id <id>     Expected Team ID (or SYSTEMEQ_TEAM_ID / DEVELOPMENT_TEAM)"
            echo "  -h, --help         Show this help message and exit"
            exit 0
            ;;
        run|--build-only|--install|--verify)
            if [[ -n "$MODE" && "$MODE" != "$1" ]]; then
                echo "Error: Conflicting mode arguments: $MODE and $1" >&2
                exit 2
            fi
            MODE="$1"
            shift
            ;;
        --ad-hoc|--adhoc)
            SIGN_STYLE="ad-hoc"
            shift
            ;;
        --identity|-i)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Error: Option $1 requires an argument." >&2
                exit 2
            fi
            IDENTITY_ARG="$2"
            shift 2
            ;;
        --team-id|-t)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Error: Option $1 requires an argument." >&2
                exit 2
            fi
            TEAM_ID_ARG="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            echo "Usage: $0 [run|--build-only|--install|--verify] [OPTIONS]" >&2
            exit 2
            ;;
    esac
done

MODE="${MODE:-run}"

if [[ "$SIGN_STYLE" == "ad-hoc" && "$MODE" != "--build-only" ]]; then
    echo "Error: --ad-hoc is only permitted with --build-only; $MODE requires stable Developer ID signing." >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${SYSTEMEQ_DERIVED_DATA:-$ROOT_DIR/DerivedData}"
APP_NAME="SystemEQ for Mac"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
INSTALLED_APP="${SYSTEMEQ_INSTALLED_APP:-/Applications/$APP_NAME.app}"
LOG_DIR="${SYSTEMEQ_LOG_DIR:-$ROOT_DIR/LocalArtifacts/LocalRun}"

CODESIGN="${SYSTEMEQ_CODESIGN_BIN:-/usr/bin/codesign}"
SECURITY="${SYSTEMEQ_SECURITY_BIN:-/usr/bin/security}"
OSASCRIPT="${SYSTEMEQ_OSASCRIPT_BIN:-/usr/bin/osascript}"
OPEN="${SYSTEMEQ_OPEN_BIN:-/usr/bin/open}"
DITTO="${SYSTEMEQ_DITTO_BIN:-/usr/bin/ditto}"
PGREP="${SYSTEMEQ_PGREP_BIN:-pgrep}"
XCODEBUILD="${SYSTEMEQ_XCODEBUILD_BIN:-xcodebuild}"

mkdir -p "$LOG_DIR"

cleanup_install_staging() {
    local path="${STAGING_DIR:-}"
    local staging_parent
    staging_parent="$(dirname "${INSTALLED_APP:-/Applications/$APP_NAME.app}")"
    if [[ -n "$path" && "$path" == "$staging_parent"/.SystemEQ-update.* && -d "$path" && ! -L "$path" ]]; then
        if [[ -d "$path/previous.app" && ! -e "$INSTALLED_APP" ]]; then
            if ! mv "$path/previous.app" "$INSTALLED_APP"; then
                echo "Error: Failed to restore previous app from staging ($path/previous.app) to $INSTALLED_APP; preserving staging for recovery." >&2
                return 1
            fi
        fi
        if [[ -d "$path/previous.app" ]]; then
            echo "Error: Staging directory contains unrecovered previous.app ($path/previous.app); preserving staging directory." >&2
            return 1
        fi
        if ! rm -rf "$path"; then
            echo "Warning: failed to remove install staging directory: $path" >&2
            return 1
        fi
    fi
    return 0
}

cleanup_all() {
    if [[ -n "${EMPTY_ENTITLEMENTS:-}" && -f "$EMPTY_ENTITLEMENTS" ]]; then
        rm -f "$EMPTY_ENTITLEMENTS"
    fi
    cleanup_install_staging
}

trap cleanup_all EXIT

stop_app() {
    if "$PGREP" -x "$APP_NAME" >/dev/null; then
        "$OSASCRIPT" -e 'tell application id "com.denzam.SystemEQ" to quit'
        for ((attempt = 0; attempt < 50; attempt++)); do
            if ! "$PGREP" -x "$APP_NAME" >/dev/null; then return; fi
            sleep 0.1
        done
        echo "SystemEQ did not quit; no app bundle was replaced." >&2
        exit 1
    fi
}

sign_bundle_inside_out() {
    local bundle="$1"
    local identity="$2"
    local main_entitlements="$ROOT_DIR/Config/SystemEQ.entitlements"

    if [[ ! -f "$main_entitlements" ]]; then
        echo "Error: Required entitlements file not found: $main_entitlements" >&2
        return 1
    fi

    EMPTY_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/systemeq-empty-ent.XXXXXX.plist")"
    cat << 'EOF' > "$EMPTY_ENTITLEMENTS"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF

    local -a components=(
        "$bundle/Contents/Frameworks/libprojectM-4.4.dylib"
        "$bundle/Contents/Frameworks/libprojectM-4-playlist.4.dylib"
        "$bundle/Contents/Helpers/ProjectMHelper.app/Contents/Frameworks/libprojectM-4.4.dylib"
        "$bundle/Contents/Helpers/ProjectMHelper.app/Contents/Frameworks/libprojectM-4-playlist.4.dylib"
        "$bundle/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
        "$bundle/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
        "$bundle/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
        "$bundle/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
        "$bundle/Contents/Frameworks/Sparkle.framework"
        "$bundle/Contents/Helpers/ProjectMHelper.app"
        "$bundle"
    )

    local autoupdate_path="$bundle/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"

    for comp in "${components[@]}"; do
        if [[ ! -e "$comp" ]]; then
            continue
        fi
        local -a cmd=("$CODESIGN" --force --sign "$identity" --timestamp=none --options runtime)
        if [[ "$comp" == "$bundle" ]]; then
            cmd+=(--entitlements "$main_entitlements")
        elif [[ "$comp" == "$autoupdate_path" ]]; then
            cmd+=(--entitlements "$EMPTY_ENTITLEMENTS")
        fi
        cmd+=("$comp")
        if ! "${cmd[@]}"; then
            echo "Error: Failed to sign component $comp" >&2
            return 1
        fi
    done

    rm -f "$EMPTY_ENTITLEMENTS"
    EMPTY_ENTITLEMENTS=""

    if ! "$CODESIGN" --verify --deep --strict "$bundle"; then
        echo "Error: Deep strict verification failed on $bundle" >&2
        return 1
    fi
    return 0
}

CHOSEN_IDENTITY=""
CHOSEN_TEAM=""

MAIN_ENTITLEMENTS="$ROOT_DIR/Config/SystemEQ.entitlements"

if [[ "$SIGN_STYLE" == "developer-id" ]]; then
    if [[ ! -f "$MAIN_ENTITLEMENTS" ]]; then
        echo "Error: Required entitlements file not found: $MAIN_ENTITLEMENTS" >&2
        exit 1
    fi

    IDENTITY_ARG="${IDENTITY_ARG:-${SYSTEMEQ_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}}"
    TEAM_ID_ARG="${TEAM_ID_ARG:-${SYSTEMEQ_TEAM_ID:-${DEVELOPMENT_TEAM:-}}}"

    INSTALLED_TEAM=""
    if [[ -e "$INSTALLED_APP" ]]; then
        if [[ -L "$INSTALLED_APP" || ! -d "$INSTALLED_APP" ]]; then
            echo "Error: Installed app path is invalid: $INSTALLED_APP" >&2
            exit 1
        fi
        if ! app_sig="$("$CODESIGN" -dvvv "$INSTALLED_APP" 2>&1)"; then
            echo "Error: Failed to read code signature from installed app ($INSTALLED_APP): $app_sig" >&2
            exit 1
        fi
        team_pat="TeamIdentifier=([A-Za-z0-9]+)"
        if [[ "$app_sig" =~ $team_pat && "${BASH_REMATCH[1]}" != "not" ]]; then
            INSTALLED_TEAM="${BASH_REMATCH[1]}"
        fi
    fi

    EXPECTED_TEAM=""
    if [[ -n "$TEAM_ID_ARG" && -n "$INSTALLED_TEAM" ]]; then
        if [[ "$TEAM_ID_ARG" != "$INSTALLED_TEAM" ]]; then
            echo "Error: Team ID mismatch: requested $TEAM_ID_ARG but installed app has $INSTALLED_TEAM." >&2
            exit 1
        fi
        EXPECTED_TEAM="$TEAM_ID_ARG"
    elif [[ -n "$TEAM_ID_ARG" ]]; then
        EXPECTED_TEAM="$TEAM_ID_ARG"
    elif [[ -n "$INSTALLED_TEAM" ]]; then
        EXPECTED_TEAM="$INSTALLED_TEAM"
    fi

    if ! sec_output="$("$SECURITY" find-identity -p codesigning -v 2>&1)"; then
        echo "Error: Failed to query signing identities via security CLI: $sec_output" >&2
        exit 1
    fi

    if [[ -z "${sec_output//[[:space:]]/}" ]]; then
        echo "Error: security CLI returned empty response." >&2
        exit 1
    fi

    if [[ "$sec_output" =~ 0\ valid\ identities\ found ]]; then
        echo "Error: No valid code signing identities found in keychain." >&2
        exit 1
    fi

    valid_hashes=()
    valid_names=()
    valid_teams=()
    id_pat="^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-Fa-f]{40})[[:space:]]+\"Developer ID Application: (.*)\""
    team_pat="\(([^()]+)\)[[:space:]]*$"

    while IFS= read -r line; do
        if [[ "$line" =~ $id_pat ]]; then
            h="${BASH_REMATCH[1]}"
            n="${BASH_REMATCH[2]}"
            t=""
            if [[ "$n" =~ $team_pat ]]; then
                t="${BASH_REMATCH[1]}"
            fi
            valid_hashes+=("$h")
            valid_names+=("Developer ID Application: $n")
            valid_teams+=("$t")
        fi
    done <<< "$sec_output"

    if [[ ${#valid_hashes[@]} -eq 0 ]]; then
        echo "Error: No valid Developer ID Application identities found in keychain." >&2
        exit 1
    fi

    if [[ -n "$IDENTITY_ARG" ]]; then
        matched_indices=()
        for idx in "${!valid_hashes[@]}"; do
            if [[ "${valid_hashes[idx]}" == "$IDENTITY_ARG" || "${valid_names[idx]}" == *"$IDENTITY_ARG"* ]]; then
                matched_indices+=("$idx")
            fi
        done
        if [[ ${#matched_indices[@]} -eq 0 ]]; then
            echo "Error: Specified identity '$IDENTITY_ARG' not found in valid Developer ID identities." >&2
            exit 1
        elif [[ ${#matched_indices[@]} -gt 1 ]]; then
            echo "Error: Ambiguous identity selector '$IDENTITY_ARG' matched multiple identities." >&2
            exit 1
        fi
        selected_idx="${matched_indices[0]}"
        CHOSEN_IDENTITY="${valid_hashes[selected_idx]}"
        CHOSEN_TEAM="${valid_teams[selected_idx]}"
        if [[ -n "$EXPECTED_TEAM" && "$CHOSEN_TEAM" != "$EXPECTED_TEAM" ]]; then
            echo "Error: Selected identity team ($CHOSEN_TEAM) does not match expected team ($EXPECTED_TEAM)." >&2
            exit 1
        fi
    else
        matched_indices=()
        if [[ -n "$EXPECTED_TEAM" ]]; then
            for idx in "${!valid_hashes[@]}"; do
                if [[ "${valid_teams[idx]}" == "$EXPECTED_TEAM" ]]; then
                    matched_indices+=("$idx")
                fi
            done
            if [[ ${#matched_indices[@]} -eq 0 ]]; then
                echo "Error: No Developer ID Application identity found matching Team ID $EXPECTED_TEAM." >&2
                exit 1
            elif [[ ${#matched_indices[@]} -gt 1 ]]; then
                echo "Error: Multiple Developer ID Application identities found for Team ID $EXPECTED_TEAM; please specify --identity." >&2
                exit 1
            fi
        else
            for idx in "${!valid_hashes[@]}"; do
                matched_indices+=("$idx")
            done
            if [[ ${#matched_indices[@]} -gt 1 ]]; then
                echo "Error: Multiple Developer ID Application identities found in keychain; please specify --identity or --team-id." >&2
                exit 1
            fi
        fi
        selected_idx="${matched_indices[0]}"
        CHOSEN_IDENTITY="${valid_hashes[selected_idx]}"
        CHOSEN_TEAM="${valid_teams[selected_idx]}"
    fi

    if [[ -z "$CHOSEN_IDENTITY" || -z "$CHOSEN_TEAM" ]]; then
        echo "Error: Resolved signing identity has missing or invalid metadata." >&2
        exit 1
    fi
fi

if ! "$XCODEBUILD" -project "$ROOT_DIR/SystemEQ for Mac.xcodeproj" \
    -scheme "$APP_NAME" -configuration Release \
    -destination "platform=macOS,arch=arm64" -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    build >"$LOG_DIR/build.log" 2>&1; then
    tail -60 "$LOG_DIR/build.log" >&2
    exit 1
fi

if [[ "$SIGN_STYLE" == "ad-hoc" ]]; then
    if ! "$CODESIGN" --verify --deep --strict "$APP_BUNDLE"; then
        echo "Error: Ad-hoc code signature verification failed on $APP_BUNDLE" >&2
        exit 1
    fi
    echo "Release build: $APP_BUNDLE"
    exit 0
fi

if ! sign_bundle_inside_out "$APP_BUNDLE" "$CHOSEN_IDENTITY"; then
    echo "Error: Signing candidate bundle failed." >&2
    exit 1
fi

if ! check_sig="$("$CODESIGN" -dvvv "$APP_BUNDLE" 2>&1)"; then
    echo "Error: Failed to verify candidate bundle signature metadata: $check_sig" >&2
    exit 1
fi
if [[ "$check_sig" =~ Signature=adhoc ]]; then
    echo "Error: App bundle unexpectedly retains ad-hoc signature." >&2
    exit 1
fi
if [[ -n "$CHOSEN_TEAM" && ! "$check_sig" =~ TeamIdentifier=$CHOSEN_TEAM ]]; then
    echo "Error: App bundle does not contain expected TeamIdentifier: $CHOSEN_TEAM." >&2
    exit 1
fi

echo "Release build: $APP_BUNDLE"
if [[ "$MODE" == "--build-only" ]]; then exit 0; fi

stop_app

if [[ "$MODE" == "--install" ]]; then
    [[ ! -L "$INSTALLED_APP" ]] || { echo "Refusing to replace a symlink." >&2; exit 1; }
    [[ ! -e "$INSTALLED_APP" || -d "$INSTALLED_APP" ]] || {
        echo "Refusing to replace a non-directory app path." >&2
        exit 1
    }
    install_parent="$(dirname "$INSTALLED_APP")"
    STAGING_DIR="$(mktemp -d "$install_parent/.SystemEQ-update.XXXXXX")"
    "$DITTO" "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
    "$CODESIGN" --verify --deep --strict "$STAGING_DIR/$APP_NAME.app"
    BACKUP_DIR=""
    if [[ -e "$INSTALLED_APP" ]]; then
        BACKUP_DIR="$(mktemp -d "$LOG_DIR/previous.XXXXXX")"
        if ! "$DITTO" "$INSTALLED_APP" "$BACKUP_DIR/original.app" || \
            ! diff -qr "$INSTALLED_APP" "$BACKUP_DIR/original.app" >/dev/null; then
            rm -rf "$BACKUP_DIR"
            exit 1
        fi
        mv "$INSTALLED_APP" "$STAGING_DIR/previous.app"
    fi
    if ! mv "$STAGING_DIR/$APP_NAME.app" "$INSTALLED_APP"; then
        echo "Error: Failed to install $APP_NAME.app to $INSTALLED_APP." >&2
        if [[ -d "$STAGING_DIR/previous.app" && ! -e "$INSTALLED_APP" ]]; then
            if ! mv "$STAGING_DIR/previous.app" "$INSTALLED_APP"; then
                echo "Install and rollback failed; staging preserved: $STAGING_DIR; verified backup: $BACKUP_DIR/original.app" >&2
            else
                echo "Rollback succeeded: restored previous version to $INSTALLED_APP." >&2
            fi
        fi
        exit 1
    fi
    if [[ -d "$STAGING_DIR/previous.app" ]]; then
        rm -rf "$STAGING_DIR/previous.app"
    fi
    cleanup_install_staging
    STAGING_DIR=""
    APP_BUNDLE="$INSTALLED_APP"
    if [[ -n "$BACKUP_DIR" ]]; then echo "Previous version: $BACKUP_DIR"; fi
fi

"$OPEN" -n "$APP_BUNDLE"
if [[ "$MODE" == "--verify" || "$MODE" == "--install" ]]; then
    sleep 2
    "$PGREP" -x "$APP_NAME"
fi
