#!/usr/bin/env bash
# Перевіряє чи доступна нова версія BlackHole і порівнює з AppConstants.swift.
# Usage: ./Scripts/check_blackhole_updates.sh [--update]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONSTANTS_FILE="$REPO_ROOT/SystemEQ for Mac/Config/AppConstants.swift"
HOMEBREW_API="https://formulae.brew.sh/api/cask/blackhole-2ch.json"

if [[ ! -f "$CONSTANTS_FILE" ]]; then
    echo "❌ AppConstants.swift not found at: $CONSTANTS_FILE"
    exit 1
fi

echo "🔍 Checking latest BlackHole version via Homebrew API..."

LATEST=$(curl -fsSL "$HOMEBREW_API" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')

if [[ -z "$LATEST" ]]; then
    echo "❌ Could not fetch latest version."
    exit 1
fi

CURRENT=$(grep -E 'bundledVersion[[:space:]]*=[[:space:]]*"' "$CONSTANTS_FILE" | sed -E 's/.*"([^"]+)".*/\1/')

echo "   Current (AppConstants): $CURRENT"
echo "   Latest  (Homebrew):     $LATEST"

if [[ "$CURRENT" == "$LATEST" ]]; then
    echo "✅ Already up to date."
    exit 0
fi

PKG_URL="https://existential.audio/downloads/BlackHole2ch-${LATEST}.pkg"
HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" -I "$PKG_URL")

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "⚠️  New version $LATEST found, but direct .pkg URL returned HTTP $HTTP_CODE:"
    echo "    $PKG_URL"
    echo "    Verify manually before updating."
    exit 2
fi

echo "📦 New version $LATEST available."
echo "    Direct PKG:  $PKG_URL (HTTP 200)"

if [[ "${1:-}" == "--update" ]]; then
    echo "✍️  Updating AppConstants.swift..."
    MATCH_COUNT=$(grep -Ec 'bundledVersion[[:space:]]*=[[:space:]]*"' "$CONSTANTS_FILE")
    if [[ "$MATCH_COUNT" -ne 1 ]]; then
        echo "❌ Expected exactly one bundledVersion declaration, found $MATCH_COUNT."
        exit 1
    fi
    sed -i '' -E "s/(bundledVersion[[:space:]]*=[[:space:]]*)\"[^\"]+\"/\1\"$LATEST\"/" "$CONSTANTS_FILE"
    UPDATED=$(grep -E 'bundledVersion[[:space:]]*=[[:space:]]*"' "$CONSTANTS_FILE" | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ "$UPDATED" != "$LATEST" ]]; then
        echo "❌ Update failed: expected $LATEST, found $UPDATED."
        exit 1
    fi
    echo "✅ Updated to $LATEST. Review the diff and commit."
    git -C "$REPO_ROOT" diff -- "$CONSTANTS_FILE"
else
    echo ""
    echo "Run with --update to apply automatically, or edit manually:"
    echo "    $CONSTANTS_FILE"
fi
