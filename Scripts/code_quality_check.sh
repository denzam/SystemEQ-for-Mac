#!/bin/bash

# Full code quality check for SystemEQ for Mac
# Run before releases or periodically

echo "═══════════════════════════════════════════════════════════════"
echo "  SystemEQ for Mac - Code Quality Check"
echo "═══════════════════════════════════════════════════════════════"
echo ""

cd "$(dirname "$0")/.." || exit 1

ERRORS=0

# 1. SwiftFormat
echo "🎨 [1/3] SwiftFormat..."
if command -v swiftformat &> /dev/null; then
    # Gate on --lint's exit code, the same check CI runs. The old --dryrun grep
    # matched the summary line ("0/60 files would have been formatted"), so it
    # counted 1 even on a clean tree and this check could never pass.
    FORMAT_OUT=$(swiftformat "SystemEQ for Mac" --config .swiftformat --lint 2>&1)
    if [ $? -ne 0 ]; then
        UNFORMATTED=$(printf '%s\n' "$FORMAT_OUT" | grep -oE "^[0-9]+/[0-9]+ files require" | cut -d/ -f1)
        echo "   ⚠️  ${UNFORMATTED:-some} file(s) need formatting"
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
    LINT_OUT=$(swiftlint lint --config .swiftlint.yml --quiet 2>/dev/null)
    LINT_ERRORS=$(printf '%s\n' "$LINT_OUT" | grep -c "error:")
    LINT_WARNINGS=$(printf '%s\n' "$LINT_OUT" | grep -c "warning:")

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
