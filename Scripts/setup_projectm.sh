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
PROJECTM_SOURCE_COMMIT="3158ee615eaafd93a8912b5f6dd84a9c47b2e00a"
PROJECTM_TEXTURE_FIX_COMMIT="97bf8845f3c5684857e0cdef54f68942e54839b9"
REQUIRED_MIN_VERSION="4.1.5"

LIB_SEARCH_PATHS=(
    "/usr/local/lib"
    "/opt/homebrew/lib"
)
INCLUDE_SEARCH_PATHS=(
    "/usr/local/include/projectM-4"
    "/opt/homebrew/include/projectM-4"
)

if [[ $# -gt 1 ]]; then
    echo "Too many arguments. Use --help for usage." >&2
    exit 2
fi

MODE="${1:-}"
case "$MODE" in
    -h | --help)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  (no args)           Перевірка наявності libprojectM"
        echo "  --build             Зібрати з source (native arch, v$PROJECTM_VERSION)"
        echo "  --build-universal   Зібрати universal binary (arm64 + x86_64)"
        exit 0
        ;;
    "" | --build | --build-universal) ;;
    *)
        echo "❌ Невідомий аргумент: $MODE"
        echo "   Доступно: -h | --help | без аргументів | --build | --build-universal"
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

apply_texture_sampler_fix() {
    python3 - "$1/src/libprojectM/Renderer/TextureSamplerDescriptor.cpp" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
original = "    return m_texture->Empty();"
if source.count(original) != 1:
    raise SystemExit("Unexpected TextureSamplerDescriptor source; refusing to build")
path.write_text(source.replace(original, "    return !m_texture || m_texture->Empty();", 1))
PY
}

configure_projectm() {
    local source_root="$1"
    shift
    (cd "$source_root" && cmake "$@")
}

copy_missing_presets() {
    local copy_source_root="${1%/}" copy_destination_root="$2" copy_list="$3"
    local source_file relative_file destination_file
    find "$copy_source_root" -type f -print0 > "$copy_list"
    while IFS= read -r -d '' source_file; do
        relative_file="${source_file#"$copy_source_root/"}"
        destination_file="$copy_destination_root/$relative_file"
        if [[ -e "$destination_file" || -L "$destination_file" ]]; then
            continue
        fi
        mkdir -p "$(dirname "$destination_file")"
        cp "$source_file" "$destination_file"
    done < "$copy_list"
}

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
    SOURCE_COMMIT="$(git -C "$BUILD_SRC" rev-parse HEAD)"
    if [[ "$SOURCE_COMMIT" != "$PROJECTM_SOURCE_COMMIT" ]]; then
        echo "Unexpected projectM source commit; refusing to build." >&2
        exit 1
    fi
    apply_texture_sampler_fix "$BUILD_SRC"
    echo "Applied upstream texture fix $PROJECTM_TEXTURE_FIX_COMMIT"

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

    configure_projectm "$BUILD_SRC" "${CMAKE_ARGS[@]}"
    cmake --build "$BUILD_OUT" -j "$(sysctl -n hw.ncpu)"
    echo "🔐 Потрібен sudo для install у /usr/local..."
    if [[ ! -t 0 ]] || sudo -n true 2>/dev/null; then
        sudo -n cmake --install "$BUILD_OUT"
    else
        sudo cmake --install "$BUILD_OUT"
    fi

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
    if [[ $WANT_BUILD -eq 0 ]]; then
        echo ""
        echo "ℹ️  MilkDrop пресети не знайдено у $PRESETS_DIR."
        echo "   Щоб завантажити повний набір пресетів, запустіть:"
        echo "     $0 --build"
    else
        echo ""
        echo "⚠️  MilkDrop пресети не знайдено. Завантажую..."
        mkdir -p "$PRESETS_DIR"

        if [[ -L "$PRESETS_DIR" ]]; then
            echo "Preset destination must not be a symlink." >&2
            exit 1
        fi
        PRESET_LINK="$(find "$PRESETS_DIR" -type l -print -quit)"
        if [[ -n "$PRESET_LINK" ]]; then
            echo "Preset destination contains symlinks; existing files are preserved." >&2
            exit 1
        fi

        if [[ -z "$TMP_ROOT" ]]; then
            TMP_ROOT="$(mktemp -d)"
        fi
        DL_DIR="$TMP_ROOT/presets"
        mkdir -p "$DL_DIR"

        PRESETS_URL="$(python3 "$PROJECT_DIR/Scripts/verify_projectm_presets.py" --url)"
        curl -fsSL "$PRESETS_URL" -o "$DL_DIR/presets.zip"
        python3 "$PROJECT_DIR/Scripts/verify_projectm_presets.py" "$DL_DIR/presets.zip"
        unzip -q "$DL_DIR/presets.zip" -d "$DL_DIR"

        # В архіві рівно одна коренева тека; на її точну назву не покладаємось.
        EXTRACTED=("$DL_DIR"/*/)
        if [[ ${#EXTRACTED[@]} -ne 1 ]]; then
            echo "❌ Неочікувана структура архіву пресетів (${#EXTRACTED[@]} кореневих тек)."
            exit 1
        fi

        copy_missing_presets "${EXTRACTED[0]}" "$PRESETS_DIR" "$DL_DIR/preset-files"
        PRESET_COUNT="$(count_presets)"
    fi
fi

if [[ "$PRESET_COUNT" -gt 0 ]]; then
    echo "✅ $PRESET_COUNT MilkDrop пресетів готові"
fi
echo ""
echo "🎉 projectM готовий до використання."

cd "$PROJECT_DIR"
