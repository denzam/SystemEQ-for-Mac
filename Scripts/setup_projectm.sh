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
shopt -s nullglob

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECTM_VERSION="4.1.6"
REQUIRED_MIN_VERSION="4.1.5"

LIB_SEARCH_PATHS=(
    "/usr/local/lib"
    "/opt/homebrew/lib"
)
INCLUDE_SEARCH_PATHS=(
    "/usr/local/include/projectM-4"
    "/opt/homebrew/include/projectM-4"
)

MODE="${1:-}"
case "$MODE" in
    "" | --build | --build-universal) ;;
    *)
        echo "❌ Невідомий аргумент: $MODE"
        echo "   Доступно: без аргументів | --build | --build-universal"
        exit 64
        ;;
esac

WANT_BUILD=0
if [[ "$MODE" == "--build" || "$MODE" == "--build-universal" ]]; then
    WANT_BUILD=1
fi

# Уся тимчасова робота — у приватній теці від mktemp. За передбачуваним шляхом
# у /tmp інший локальний користувач може підкласти свій вміст або symlink.
TMP_ROOT=""
cleanup() {
    if [[ -n "$TMP_ROOT" && -d "$TMP_ROOT" ]]; then
        rm -rf "$TMP_ROOT"
    fi
}
trap cleanup EXIT

# `[[ "4.1.10" < "4.1.5" ]]` порівнює РЯДКИ і вважає 4.1.10 старішою, тому
# порівняння версій іде через sort -V.
version_lt() {
    if [[ "$1" == "$2" ]]; then
        return 1
    fi
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

# Шукає НАЙНОВІШУ реальну бібліотеку: поруч можуть лежати кілька версій
# (4.1.5 і 4.1.6 одночасно), а алфавітно перша з них — найстаріша.
# Symlink'и пропускаються, бо вказують на ті самі файли.
# Результат: FOUND_LIB, INSTALLED_VERSION.
FOUND_LIB=""
INSTALLED_VERSION=""
find_newest_lib() {
    FOUND_LIB=""
    INSTALLED_VERSION=""
    local path candidate ver
    for path in "$@"; do
        for candidate in "$path"/libprojectM-4.*.dylib; do
            if [[ ! -f "$candidate" || -L "$candidate" ]]; then
                continue
            fi
            ver="$(basename "$candidate" | sed -E 's/^libprojectM-4\.([0-9]+(\.[0-9]+)*)\.dylib$/\1/')"
            if [[ ! "$ver" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
                continue
            fi
            if [[ -z "$INSTALLED_VERSION" ]] || version_lt "$INSTALLED_VERSION" "$ver"; then
                INSTALLED_VERSION="$ver"
                FOUND_LIB="$candidate"
            fi
        done
        if [[ -n "$FOUND_LIB" ]]; then
            return 0
        fi
    done
    return 0
}

echo "🎨 SystemEQ — projectM setup (target v$PROJECTM_VERSION)"
echo ""

# --- 1. Пошук встановленої бібліотеки ---
find_newest_lib "${LIB_SEARCH_PATHS[@]}"

FOUND_HEADER=""
for path in "${INCLUDE_SEARCH_PATHS[@]}"; do
    if [[ -f "$path/projectM.h" ]]; then
        FOUND_HEADER="$path"
        break
    fi
done

if [[ -n "$FOUND_LIB" && -n "$FOUND_HEADER" ]]; then
    echo "✅ libprojectM знайдено: $FOUND_LIB (v$INSTALLED_VERSION)"
    echo "✅ headers:              $FOUND_HEADER"

    if version_lt "$INSTALLED_VERSION" "$REQUIRED_MIN_VERSION"; then
        echo "⚠️  Версія $INSTALLED_VERSION нижча за мінімальну $REQUIRED_MIN_VERSION."
        if [[ $WANT_BUILD -eq 0 ]]; then
            echo "    Запусти: $0 --build"
            exit 2
        fi
    fi
else
    echo "❌ libprojectM-4 не знайдено."
    if [[ -z "$FOUND_LIB" ]]; then
        echo "   Перевірені шляхи для .dylib: ${LIB_SEARCH_PATHS[*]}"
    fi
    if [[ -z "$FOUND_HEADER" ]]; then
        echo "   Перевірені шляхи для headers: ${INCLUDE_SEARCH_PATHS[*]}"
    fi
    echo ""
    echo "   Homebrew стабільний pkg = 3.1.12 (застарілий, несумісний)."
    echo "   Щоб зібрати v$PROJECTM_VERSION з source:"
    echo "     $0 --build"

    if [[ $WANT_BUILD -eq 0 ]]; then
        exit 1
    fi
fi

# --- 2. Збірка з source (--build або --build-universal) ---
if [[ $WANT_BUILD -eq 1 ]]; then
    UNIVERSAL=0
    if [[ "$MODE" == "--build-universal" ]]; then
        UNIVERSAL=1
    fi

    echo ""
    if [[ $UNIVERSAL -eq 1 ]]; then
        echo "🔨 Збірка projectM v$PROJECTM_VERSION (universal: arm64 + x86_64)..."
    else
        echo "🔨 Збірка projectM v$PROJECTM_VERSION (native arch)..."
    fi

    if ! command -v cmake >/dev/null 2>&1; then
        echo "❌ cmake не знайдено. brew install cmake"
        exit 1
    fi

    TMP_ROOT="$(mktemp -d)"
    BUILD_SRC="$TMP_ROOT/projectm"
    BUILD_OUT="$TMP_ROOT/projectm-build"

    git clone --depth 1 --branch "v$PROJECTM_VERSION" --recurse-submodules \
        https://github.com/projectM-visualizer/projectm.git "$BUILD_SRC"

    CMAKE_ARGS=(
        -S "$BUILD_SRC"
        -B "$BUILD_OUT"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX=/usr/local
        -DENABLE_PLAYLIST=ON
    )
    if [[ $UNIVERSAL -eq 1 ]]; then
        CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0)
    fi

    cmake "${CMAKE_ARGS[@]}"
    cmake --build "$BUILD_OUT" -j "$(sysctl -n hw.ncpu)"
    echo "🔐 Потрібен sudo для install у /usr/local..."
    sudo cmake --install "$BUILD_OUT"

    echo "✅ projectM v$PROJECTM_VERSION встановлено."

    find_newest_lib "${LIB_SEARCH_PATHS[@]}"
    if [[ -n "$FOUND_LIB" ]]; then
        echo "🔍 Активна версія: v$INSTALLED_VERSION"
        if [[ $UNIVERSAL -eq 1 ]]; then
            echo "🔍 Архітектури: $(lipo -archs "$FOUND_LIB")"
        fi
    fi
    echo "⚠️  Перевір Build Settings у Xcode — вони можуть посилатися на стару версію."
fi

# --- 3. MilkDrop пресети ---
PRESETS_DIR="$HOME/Library/Application Support/SystemEQ/presets"

# На свіжому Mac теки ще немає: find завершується ненульовим кодом, pipefail
# його пропускає і set -e вбиває скрипт до завантаження пресетів.
count_presets() {
    if [[ ! -d "$PRESETS_DIR" ]]; then
        echo 0
        return 0
    fi
    find "$PRESETS_DIR" -name "*.milk" -type f | wc -l | tr -d ' '
}

PRESET_COUNT="$(count_presets)"

if [[ "$PRESET_COUNT" -eq 0 ]]; then
    echo ""
    echo "⚠️  MilkDrop пресети не знайдено. Завантажую..."
    mkdir -p "$PRESETS_DIR"

    if [[ -z "$TMP_ROOT" ]]; then
        TMP_ROOT="$(mktemp -d)"
    fi
    DL_DIR="$TMP_ROOT/presets"
    mkdir -p "$DL_DIR"

    curl -fsSL \
        "https://github.com/projectM-visualizer/presets-cream-of-the-crop/archive/refs/heads/master.zip" \
        -o "$DL_DIR/presets.zip"
    unzip -q "$DL_DIR/presets.zip" -d "$DL_DIR"

    # В архіві рівно одна коренева тека; на її точну назву не покладаємось.
    EXTRACTED=("$DL_DIR"/*/)
    if [[ ${#EXTRACTED[@]} -ne 1 ]]; then
        echo "❌ Неочікувана структура архіву пресетів (${#EXTRACTED[@]} кореневих тек)."
        exit 1
    fi

    cp -R "${EXTRACTED[0]}." "$PRESETS_DIR/"
    PRESET_COUNT="$(count_presets)"
fi

echo "✅ $PRESET_COUNT MilkDrop пресетів готові"
echo ""
echo "🎉 projectM готовий до використання."

cd "$PROJECT_DIR"
