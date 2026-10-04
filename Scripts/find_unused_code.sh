#!/bin/bash
set -euo pipefail

# Find unused code in SystemEQ for Mac using Periphery
# Run this script periodically to clean up dead code

echo "🔍 Scanning for unused code..."
echo ""

cd "$(dirname "$0")/.." || exit 1

if ! command -v periphery &>/dev/null; then
    echo "❌ periphery not found. Install with: brew install peripheryapp/periphery/periphery" >&2
    exit 1
fi

# Run Periphery scan
if periphery scan \
    --project "SystemEQ for Mac.xcodeproj" \
    --schemes "SystemEQ for Mac" \
    --targets "SystemEQ for Mac" \
    --skip-build \
    --format xcode \
    --disable-update-check; then
    echo ""
    echo "✅ Scan complete!"
    echo "   Review the results above and remove unused code."
else
    STATUS=$?
    echo "" >&2
    echo "⚠️  Periphery scan failed (exit code $STATUS)." >&2
    echo "   If this is the first run, Xcode build may be required:" >&2
    echo "   1. Open Xcode and build the project (Cmd+B)" >&2
    echo "   2. Run this script again" >&2
    echo "" >&2
    echo "   Or run with build:" >&2
    echo "   periphery scan --project 'SystemEQ for Mac.xcodeproj' --schemes 'SystemEQ for Mac' --targets 'SystemEQ for Mac'" >&2
    exit "$STATUS"
fi
