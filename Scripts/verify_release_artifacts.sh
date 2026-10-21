#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTRIBUTION_TEAM=""

verify_architectures() {
    local architectures
    architectures=$(lipo -archs "$1")
    [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]]
}

verify_bundle() {
    local bundle="$1" version="$2" component executable library architecture dependency dependencies
    test -d "$bundle"
    codesign --verify --deep --strict "$bundle"
    test -f "$bundle/Contents/Resources/Assets.car"
    if [[ ! -f "$bundle/Contents/Resources/EQDatabase.db" ]]; then
        test -f "$bundle/Contents/Resources/Resources/EQDatabase.db"
    fi
    for component in "$bundle" "$bundle/Contents/Helpers/ProjectMHelper.app"; do
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$component/Contents/Info.plist")" = "$version"
        executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$component/Contents/Info.plist")
        codesign --verify --deep --strict "$component"
        verify_architectures "$component/Contents/MacOS/$executable"
        for library in libprojectM-4.4.dylib libprojectM-4-playlist.4.dylib; do
            test -f "$component/Contents/Frameworks/$library"
            verify_architectures "$component/Contents/Frameworks/$library"
        done
        for architecture in arm64 x86_64; do
            for library in "$component/Contents/MacOS/$executable" "$component/Contents/Frameworks/"*.dylib; do
                dependencies=$(otool -arch "$architecture" -L "$library")
                while IFS= read -r dependency; do
                    dependency="${dependency%% (compatibility version*}"
                    dependency="${dependency#${dependency%%[![:space:]]*}}"
                    case "$dependency" in
                        /opt/homebrew/*|/usr/local/*|/Users/*|/private/tmp/*)
                            echo "Unbundled developer dependency: $dependency" >&2
                            return 1 ;;
                        @rpath/libprojectM*) test -f "$component/Contents/Frameworks/${dependency#@rpath/}" ;;
                    esac
                done <<< "${dependencies#*$'\n'}"
            done
        done
    done
    if [[ -n "$DISTRIBUTION_TEAM" ]]; then
        bash "$SCRIPT_DIR/prepare_signed_release.sh" --verify-bundle "$bundle" --team "$DISTRIBUTION_TEAM" --version "$version"
        xcrun stapler validate "$bundle"
        spctl --assess --type execute --verbose=4 "$bundle"
    fi
}

if [[ $# -eq 3 && "$1" == "--bundle" ]]; then
    verify_bundle "$2" "$3"
    exit 0
fi
if [[ $# -eq 5 && "$1" == "--distribution" ]]; then
    DISTRIBUTION_TEAM="$2"
    if ! [[ "$DISTRIBUTION_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
        echo "Invalid Developer Team ID" >&2
        exit 2
    fi
    shift 2
fi
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 ZIP DMG VERSION | --bundle APP VERSION | --distribution TEAM ZIP DMG VERSION" >&2
    exit 2
fi
test -f "$1"
test -f "$2"
if [[ -n "$DISTRIBUTION_TEAM" ]]; then
    codesign --verify --strict -R "=anchor apple generic and certificate leaf[subject.OU] = \"$DISTRIBUTION_TEAM\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" "$2"
    DETAILS=$(codesign --display --verbose=4 "$2" 2>&1)
    python3 - "$DISTRIBUTION_TEAM" "$DETAILS" <<'PY'
import re, sys
team, details = sys.argv[1:]
if not (f"TeamIdentifier={team}\n" in details and "Authority=Developer ID Application:" in details
        and "Signature=adhoc" not in details and re.search(r"^Timestamp=(?!none\s*$).+", details, re.MULTILINE)):
    raise SystemExit("Invalid Developer ID DMG signature or timestamp")
PY
    xcrun stapler validate "$2"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$2"
fi
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/systemeq-packages.XXXXXX")
MOUNTED=0
cleanup() {
    local status=$?
    trap - EXIT
    if [[ "$MOUNTED" == 1 ]]; then
        if ! hdiutil detach "$WORK_DIR/mount" -force; then
            echo "Failed to detach; preserving work directory: $WORK_DIR" >&2
            if [[ "$status" == 0 ]]; then status=1; fi
            exit "$status"
        fi
    fi
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        if ! rm -rf "$WORK_DIR"; then
            if [[ "$status" == 0 ]]; then status=1; fi
        fi
    fi
    if [[ "$status" == 0 ]]; then echo "ZIP and DMG bundle checks passed."; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ditto -x -k "$1" "$WORK_DIR/zip"
verify_bundle "$WORK_DIR/zip/SystemEQ for Mac.app" "$3"
mkdir "$WORK_DIR/mount"
MOUNTED=1
hdiutil attach "$2" -readonly -nobrowse -mountpoint "$WORK_DIR/mount" >/dev/null
verify_bundle "$WORK_DIR/mount/SystemEQ for Mac.app" "$3"
python3 - "$WORK_DIR/zip/SystemEQ for Mac.app" "$WORK_DIR/mount/SystemEQ for Mac.app" <<'PY'
import hashlib, os, sys
from pathlib import Path
def inventory(root):
    root = Path(root).resolve(strict=True)
    files = {}
    for path in root.rglob("*"):
        key = str(path.relative_to(root))
        if path.is_symlink():
            if not path.resolve(strict=True).is_relative_to(root):
                raise SystemExit("Escaping package symlink")
            files[key] = ("link", os.readlink(path))
        elif path.is_file():
            files[key] = ("file", hashlib.sha256(path.read_bytes()).hexdigest())
        elif not path.is_dir():
            raise SystemExit("Unsupported package entry")
    return files
if inventory(sys.argv[1]) != inventory(sys.argv[2]):
    raise SystemExit("ZIP and DMG contain different applications")
PY
