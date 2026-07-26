#!/bin/bash

# Find unused code in SystemEQ for Mac using Periphery
# Run this script periodically to clean up dead code

echo "🔍 Scanning for unused code..."
echo ""

cd "$(dirname "$0")/.." || exit 1

# Run Periphery scan
if periphery scan \
    --project "SystemEQ for Mac.xcodeproj" \
    --schemes "SystemEQ for Mac" \
    --targets "SystemEQ for Mac" \
    --skip-build \
    --format xcode \
    --disable-update-check \
    2>/dev/null; then
    echo ""
    echo "✅ Scan complete!"
    echo "   Review the results above and remove unused code."
else
    echo ""
    echo "⚠️  First run requires building the project:"
    echo "   1. Open Xcode and build the project (Cmd+B)"
    echo "   2. Run this script again"
    echo ""
    echo "   Or run with build:"
    echo "   periphery scan --project 'SystemEQ for Mac.xcodeproj' --schemes 'SystemEQ for Mac' --targets 'SystemEQ for Mac'"
fi
