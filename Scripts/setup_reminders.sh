#!/bin/bash
set -u

if [[ $# -eq 1 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
    echo "Usage: $0"
    exit 0
fi
if [[ $# -ne 0 ]]; then
    echo "Unsupported arguments. Usage: $0" >&2
    exit 2
fi

# Setup periodic reminders for SystemEQ maintenance tasks
# Uses macOS Calendar/Reminders to create recurring events

echo "📅 Setting up maintenance reminders..."
echo ""

if ! command -v osascript &>/dev/null; then
    echo "❌ osascript not available in this environment." >&2
    exit 1
fi

CREATED=0
ERRORS=0

# 1. Weekly reminder - Find unused code
if osascript <<EOF
tell application "Reminders"
    tell first list
        make new reminder with properties {name:"🧹 SystemEQ: Перевірити невикористаний код", body:"Запустити: ./Scripts/find_unused_code.sh

Це допоможе тримати код чистим.", due date:(current date) + 7 * days}
    end tell
end tell
EOF
then
    echo "✅ Створено нагадування: Перевірка невикористаного коду (щотижня)"
    CREATED=$((CREATED + 1))
else
    echo "❌ Не вдалося створити нагадування: Перевірка невикористаного коду" >&2
    ERRORS=$((ERRORS + 1))
fi

# 2. Monthly reminder - Full code audit
if osascript <<EOF
tell application "Reminders"
    tell first list
        make new reminder with properties {name:"🔍 SystemEQ: Повний аудит коду", body:"Запустити: ./Scripts/code_quality_check.sh

Перевірка перед релізом:
• SwiftFormat
• SwiftLint  
• Build test", due date:(current date) + 30 * days}
    end tell
end tell
EOF
then
    echo "✅ Створено нагадування: Повний аудит коду (щомісяця)"
    CREATED=$((CREATED + 1))
else
    echo "❌ Не вдалося створити нагадування: Повний аудит коду" >&2
    ERRORS=$((ERRORS + 1))
fi

# 3. Monthly reminder - Update dependencies
if osascript <<EOF
tell application "Reminders"
    tell first list
        make new reminder with properties {name:"📦 SystemEQ: Оновити залежності", body:"Перевірити оновлення:
• brew upgrade swiftformat swiftlint periphery
• Перевірити GitHub Actions
• Оновити Xcode якщо потрібно", due date:(current date) + 30 * days}
    end tell
end tell
EOF
then
    echo "✅ Створено нагадування: Оновлення залежностей (щомісяця)"
    CREATED=$((CREATED + 1))
else
    echo "❌ Не вдалося створити нагадування: Оновлення залежностей" >&2
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ "$ERRORS" -eq 0 ] && [ "$CREATED" -eq 3 ]; then
    echo "  📱 Нагадування успішно створені в додатку Reminders! ($CREATED/3)"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  Розклад:"
    echo "  • Щотижня: Перевірка невикористаного коду"
    echo "  • Щомісяця: Повний аудит коду"
    echo "  • Щомісяця: Оновлення залежностей"
    echo ""
    echo "  💡 Відкрийте Reminders щоб налаштувати повторення"
    exit 0
else
    echo "  ❌ Помилка: створено $CREATED/3 нагадувань ($ERRORS помилок)." >&2
    echo "     Перевірте дозволи доступу до Reminders (Automation permissions)." >&2
    echo "═══════════════════════════════════════════════════════════════" >&2
    exit 1
fi
