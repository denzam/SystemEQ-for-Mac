#!/bin/bash
# build.sh — SystemEQ for Mac
# Запускає xcodebuild, зберігає повний лог у build.log,
# і виводить у термінал тільки помилки та попередження.
#
# Використання:
#   ./build.sh            # Debug збірка (за замовчуванням)
#   ./build.sh release    # Release збірка
#   ./build.sh clean      # Очистити DerivedData і зібрати знову

set -euo pipefail

PROJECT="SystemEQ for Mac.xcodeproj"
SCHEME="SystemEQ for Mac"
CONFIG="Debug"
LOG="build.log"

# Обробка аргументів
if [[ "${1:-}" == "release" ]]; then
    CONFIG="Release"
elif [[ "${1:-}" == "clean" ]]; then
    echo "Cleaning DerivedData..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" clean 2>&1 | tail -1
fi

echo "Building $SCHEME ($CONFIG)..."
echo "Full log: $(pwd)/$LOG"
echo "---"

# Запуск збірки — повний лог у файл, стислий вивід у термінал
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    build 2>&1 | tee "$LOG" | \
    grep --line-buffered -E \
        "^(.*error:|.*warning:|Build succeeded|BUILD SUCCEEDED|BUILD FAILED|.*: error |.*: warning )" | \
    grep -v "appintentsmetadataprocessor" | \
    grep -v "^$"

EXIT_CODE=${PIPESTATUS[0]}

echo "---"
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "BUILD SUCCEEDED"
else
    echo "BUILD FAILED (exit code $EXIT_CODE)"
    echo ""
    echo "Повні помилки:"
    grep -E "error:" "$LOG" | grep -v "appintentsmetadataprocessor" || true
fi

exit "$EXIT_CODE"
