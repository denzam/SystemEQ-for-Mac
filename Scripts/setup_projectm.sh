#!/usr/bin/env bash
#
# setup_projectm.sh
# Перевіряє/встановлює libprojectM 4.x для SystemEQ.
#
# Usage:
#   ./Scripts/setup_projectm.sh                       # лише перевірка
#   ./Scripts/setup_projectm.sh --build              # зібрати з source (native arch, v4.1.6)
#   ./Scripts/setup_projectm.sh --build-universal    # universal binary (arm64 + x86_64) для Intel+AS
#

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECTM_VERSION="4.1.6"
REQUIRED_MIN_VERSION="4.1.5"

# Шляхи до бібліотек (перевіряються в порядку пріоритету)
LIB_SEARCH_PATHS=(
    "/usr/local/lib"
    "/opt/homebrew/lib"
)
INCLUDE_SEARCH_PATHS=(
    "/usr/local/include/projectM-4"
    "/opt/homebrew/include/projectM-4"
)

echo "🎨 SystemEQ — projectM setup (target v$PROJECTM_VERSION)"
echo ""

# --- 1. Пошук встановленої бібліотеки ---
FOUND_LIB=""
FOUND_LIB_PATH=""
for path in "${LIB_SEARCH_PATHS[@]}"; do
    matches=$(ls "$path"/libprojectM-4.*.dylib 2>/dev/null | grep -v playlist || true)
    if [[ -n "$matches" ]]; then
        FOUND_LIB=$(echo "$matches" | head -1)
        FOUND_LIB_PATH="$path"
        break
    fi
done

FOUND_HEADER=""
for path in "${INCLUDE_SEARCH_PATHS[@]}"; do
    if [[ -f "$path/projectM.h" ]]; then
        FOUND_HEADER="$path"
        break
    fi
done

if [[ -n "$FOUND_LIB" && -n "$FOUND_HEADER" ]]; then
    INSTALLED_VERSION=$(basename "$FOUND_LIB" | sed -E 's/libprojectM-4\.([0-9.]+)\.dylib/\1/')
    echo "✅ libprojectM знайдено: $FOUND_LIB (v$INSTALLED_VERSION)"
    echo "✅ headers:              $FOUND_HEADER"

    if [[ "$INSTALLED_VERSION" < "$REQUIRED_MIN_VERSION" ]]; then
        echo "⚠️  Версія $INSTALLED_VERSION нижча за мінімальну $REQUIRED_MIN_VERSION."
        echo "    Запусти: $0 --build"
        exit 2
    fi
else
    echo "❌ libprojectM-4 не знайдено."
    [[ -z "$FOUND_LIB" ]] && echo "   Перевірені шляхи для .dylib: ${LIB_SEARCH_PATHS[*]}"
    [[ -z "$FOUND_HEADER" ]] && echo "   Перевірені шляхи для headers: ${INCLUDE_SEARCH_PATHS[*]}"
    echo ""
    echo "   Homebrew стабільний pkg = 3.1.12 (застарілий, несумісний)."
    echo "   Щоб зібрати v$PROJECTM_VERSION з source:"
    echo "     $0 --build"

    if [[ "${1:-}" != "--build" && "${1:-}" != "--build-universal" ]]; then
        exit 1
    fi
fi

# --- 2. Збірка з source (--build або --build-universal) ---
if [[ "${1:-}" == "--build" || "${1:-}" == "--build-universal" ]]; then
    UNIVERSAL=0
    [[ "${1:-}" == "--build-universal" ]] && UNIVERSAL=1

    echo ""
    if [[ $UNIVERSAL -eq 1 ]]; then
        echo "🔨 Збірка projectM v$PROJECTM_VERSION (universal: arm64 + x86_64)..."
    else
        echo "🔨 Збірка projectM v$PROJECTM_VERSION (native arch)..."
    fi

    command -v cmake >/dev/null 2>&1 || { echo "❌ cmake не знайдено. brew install cmake"; exit 1; }

    BUILD_DIR="/tmp/projectm-build-$PROJECTM_VERSION"
    rm -rf "$BUILD_DIR"
    git clone --depth 1 --branch "v$PROJECTM_VERSION" --recurse-submodules \
        https://github.com/projectM-visualizer/projectm.git "$BUILD_DIR"

    cd "$BUILD_DIR"
    CMAKE_ARGS=(-S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DENABLE_PLAYLIST=ON)
    if [[ $UNIVERSAL -eq 1 ]]; then
        CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0)
    fi
    cmake "${CMAKE_ARGS[@]}"
    cmake --build build -j "$(sysctl -n hw.ncpu)"
    echo "🔐 Потрібен sudo для install у /usr/local..."
    sudo cmake --install build

    echo "✅ projectM v$PROJECTM_VERSION встановлено."
    if [[ $UNIVERSAL -eq 1 ]]; then
        INSTALLED_DYLIB=$(ls /usr/local/lib/libprojectM-4.*.dylib 2>/dev/null | grep -v playlist | head -1)
        if [[ -n "$INSTALLED_DYLIB" ]]; then
            echo "🔍 Архітектури: $(lipo -archs "$INSTALLED_DYLIB")"
        fi
    fi
    echo "⚠️  Перевір Build Settings у Xcode — вони можуть посилатися на стару версію."
    cd "$PROJECT_DIR"
fi

# --- 3. MilkDrop пресети ---
PRESETS_DIR="$HOME/Library/Application Support/SystemEQ/presets"
PRESET_COUNT=$(find "$PRESETS_DIR" -name "*.milk" 2>/dev/null | wc -l | tr -d ' ')

if [[ "$PRESET_COUNT" -eq 0 ]]; then
    echo ""
    echo "⚠️  MilkDrop пресети не знайдено. Завантажую..."
    mkdir -p "$PRESETS_DIR"
    TMP_ZIP="/tmp/milkdrop-presets.zip"
    curl -fsSL "https://github.com/projectM-visualizer/presets-cream-of-the-crop/archive/refs/heads/master.zip" -o "$TMP_ZIP"
    unzip -q "$TMP_ZIP" -d /tmp/
    mv /tmp/presets-cream-of-the-crop-master/* "$PRESETS_DIR/"
    rm -rf "$TMP_ZIP" /tmp/presets-cream-of-the-crop-master
    PRESET_COUNT=$(find "$PRESETS_DIR" -name "*.milk" | wc -l | tr -d ' ')
fi

echo "✅ $PRESET_COUNT MilkDrop пресетів готові"
echo ""
echo "🎉 projectM готовий до використання."
