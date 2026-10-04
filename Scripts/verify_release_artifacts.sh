#!/bin/bash
set -euo pipefail

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
}

if [[ $# -eq 3 && "$1" == "--bundle" ]]; then
    verify_bundle "$2" "$3"
    exit 0
fi
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 ZIP DMG VERSION | --bundle APP VERSION" >&2
    exit 2
fi
test -f "$1"
test -f "$2"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/systemeq-packages.XXXXXX")
MOUNTED=0
cleanup() {
    if [[ "$MOUNTED" == 1 ]]; then
        if ! hdiutil detach "$WORK_DIR/mount" -force >/dev/null 2>&1; then
            echo "Warning: failed to cleanly detach $WORK_DIR/mount" >&2
        fi
    fi
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT
ditto -x -k "$1" "$WORK_DIR/zip"
verify_bundle "$WORK_DIR/zip/SystemEQ for Mac.app" "$3"
mkdir "$WORK_DIR/mount"
hdiutil attach "$2" -readonly -nobrowse -mountpoint "$WORK_DIR/mount" >/dev/null
MOUNTED=1
verify_bundle "$WORK_DIR/mount/SystemEQ for Mac.app" "$3"
echo "ZIP and DMG bundle checks passed."
