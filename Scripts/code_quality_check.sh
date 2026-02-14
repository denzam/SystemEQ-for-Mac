#!/bin/bash

# Full code quality check for SystemEQ for Mac
# Run before releases or periodically

echo "═══════════════════════════════════════════════════════════════"
echo "  SystemEQ for Mac - Code Quality Check"
echo "═══════════════════════════════════════════════════════════════"
echo ""

cd "$(dirname "$0")/.."

ERRORS=0

# 1. SwiftFormat
echo "🎨 [1/3] SwiftFormat..."
if command -v swiftformat &> /dev/null; then
    UNFORMATTED=$(swiftformat "SystemEQ for Mac" --config .swiftformat --dryrun 2>&1 | grep "would have" | wc -l)
    if [ "$UNFORMATTED" -gt 0 ]; then
        echo "   ⚠️  $UNFORMATTED file(s) need formatting"
        echo "   Run: swiftformat 'SystemEQ for Mac' --config .swiftformat"
        ERRORS=$((ERRORS + 1))
    else
        echo "   ✅ All files formatted correctly"
    fi
else
    echo "   ⚠️  SwiftFormat not installed"
fi
echo ""

# 2. SwiftLint
echo "🔎 [2/3] SwiftLint..."
if command -v swiftlint &> /dev/null; then
    LINT_ERRORS=$(swiftlint lint --config .swiftlint.yml 2>/dev/null | grep "error:" | wc -l)
    LINT_WARNINGS=$(swiftlint lint --config .swiftlint.yml 2>/dev/null | grep "warning:" | wc -l)
    
    if [ "$LINT_ERRORS" -gt 0 ]; then
        echo "   ❌ $LINT_ERRORS error(s), $LINT_WARNINGS warning(s)"
        echo "   Run: swiftlint --fix"
        ERRORS=$((ERRORS + 1))
    else
        echo "   ✅ No errors ($LINT_WARNINGS warnings)"
    fi
else
    echo "   ⚠️  SwiftLint not installed"
fi
echo ""

# 3. Build check
echo "🔨 [3/3] Build check..."
xcodebuild -project "SystemEQ for Mac.xcodeproj" -scheme "SystemEQ for Mac" -configuration Debug build -quiet 2>/dev/null
if [ $? -eq 0 ]; then
    echo "   ✅ Build successful"
else
    echo "   ❌ Build failed"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Summary
echo "═══════════════════════════════════════════════════════════════"
if [ $ERRORS -eq 0 ]; then
    echo "  ✅ All checks passed! Code is ready."
else
    echo "  ❌ $ERRORS check(s) failed. Please fix before release."
fi
echo "═══════════════════════════════════════════════════════════════"

exit $ERRORS
