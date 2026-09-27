#!/bin/bash

# Full code quality check for SystemEQ for Mac
# Run before releases or periodically

echo "═══════════════════════════════════════════════════════════════"
echo "  SystemEQ for Mac - Code Quality Check"
echo "═══════════════════════════════════════════════════════════════"
echo ""

cd "$(dirname "$0")/.." || exit 1

MODE="${1:-build}"
if [ "$MODE" != "build" ] && [ "$MODE" != "--full" ]; then
    echo "Usage: $0 [--full]"
    exit 2
fi

ERRORS=0

echo "🧹 [1/5] Git whitespace..."
if git diff --check && git diff --cached --check; then
    echo "   ✅ No whitespace errors"
else
    echo "   ❌ Whitespace errors found"
    ERRORS=$((ERRORS + 1))
fi
echo ""

echo "🎨 [2/5] SwiftFormat..."
if command -v swiftformat &> /dev/null; then
    # Gate on --lint's exit code, the same check CI runs. The old --dryrun grep
    # matched the summary line ("0/60 files would have been formatted"), so it
    # counted 1 even on a clean tree and this check could never pass.
    if FORMAT_OUT=$(swiftformat "SystemEQ for Mac" --config .swiftformat --lint 2>&1); then
        echo "   ✅ All files formatted correctly"
    else
        UNFORMATTED=$(printf '%s\n' "$FORMAT_OUT" | grep -oE "^[0-9]+/[0-9]+ files require" | cut -d/ -f1)
        echo "   ⚠️  ${UNFORMATTED:-some} file(s) need formatting"
        echo "   Run: swiftformat 'SystemEQ for Mac' --config .swiftformat"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "   ⚠️  SwiftFormat not installed"
fi
echo ""

echo "🔎 [3/5] SwiftLint..."
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

echo "🐍 [4/5] Python checks..."
PYTHON_FILES=()
while IFS= read -r -d '' file; do
    PYTHON_FILES+=("$file")
done < <(git ls-files -z -co --exclude-standard -- '*.py')

if [ "${#PYTHON_FILES[@]}" -eq 0 ]; then
    echo "   ✅ No Python files found"
elif python3 - "${PYTHON_FILES[@]}" <<'PYTHON'
from pathlib import Path
import sys

failed = False
for path in sys.argv[1:]:
    try:
        compile(Path(path).read_bytes(), path, "exec", dont_inherit=True)
    except (OSError, SyntaxError, ValueError) as error:
        print(f"{path}: {error}", file=sys.stderr)
        failed = True
sys.exit(1 if failed else 0)
PYTHON
then
    echo "   ✅ Python syntax is valid"
else
    echo "   ❌ Python syntax check failed"
    ERRORS=$((ERRORS + 1))
fi
if [ -f ".agents/skills/task-router/scripts/test_route.py" ]; then
    if python3 ".agents/skills/task-router/scripts/test_route.py"; then
        echo "   ✅ Task-router tests passed"
    else
        echo "   ❌ Task-router tests failed"
        ERRORS=$((ERRORS + 1))
    fi
fi
echo ""

if [ "$MODE" = "--full" ]; then
    echo "🧪 [5/5] Test check..."
    XCODE_ACTION="test"
else
    echo "🔨 [5/5] Build check..."
    XCODE_ACTION="build"
fi
if xcodebuild -project "SystemEQ for Mac.xcodeproj" -scheme "SystemEQ for Mac" \
    -configuration Debug "$XCODE_ACTION" -destination "platform=macOS" \
    -derivedDataPath "${TMPDIR:-/tmp}/systemeq-derived-data" \
    CODE_SIGNING_ALLOWED=NO -quiet 2>/dev/null; then
    if [ "$MODE" = "--full" ]; then
        echo "   ✅ Tests passed"
    else
        echo "   ✅ Build successful"
    fi
else
    if [ "$MODE" = "--full" ]; then
        echo "   ❌ Tests failed"
    else
        echo "   ❌ Build failed"
    fi
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
