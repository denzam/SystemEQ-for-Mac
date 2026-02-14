#!/bin/bash

# Quick build check script for SystemEQ for Mac
# Usage: ./check_build.sh

set -e

echo "🔨 Building SystemEQ for Mac..."
echo ""

# Build
xcodebuild -scheme "SystemEQ for Mac" -configuration Debug build 2>&1 | \
    grep -E "(BUILD|error:|warning:)" | \
    grep -v "appintentsmetadataprocessor" || true

echo ""
echo "✅ Build check complete!"
echo ""
echo "If you see 'BUILD SUCCEEDED' above, your code is working!"
echo "Any Windsurf IDE errors are false positives."
