#!/bin/bash

# Setup periodic reminders for SystemEQ maintenance tasks
# Uses macOS Calendar to create recurring events

echo "📅 Setting up maintenance reminders..."
echo ""

# Create reminders using osascript (AppleScript)

# 1. Weekly reminder - Find unused code
osascript <<EOF
tell application "Reminders"
    tell first list
        make new reminder with properties {name:"🧹 SystemEQ: Перевірити невикористаний код", body:"Запустити: ./Scripts/find_unused_code.sh

Це допоможе тримати код чистим.", due date:(current date) + 7 * days}
    end tell
end tell
EOF

if [ $? -eq 0 ]; then
    echo "✅ Створено нагадування: Перевірка невикористаного коду (щотижня)"
else
    echo "⚠️  Не вдалося створити нагадування. Спробуйте вручну."
fi

# 2. Monthly reminder - Full code audit
osascript <<EOF
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

if [ $? -eq 0 ]; then
    echo "✅ Створено нагадування: Повний аудит коду (щомісяця)"
else
    echo "⚠️  Не вдалося створити нагадування."
fi

# 3. Monthly reminder - Update dependencies
osascript <<EOF
tell application "Reminders"
    tell first list
        make new reminder with properties {name:"📦 SystemEQ: Оновити залежності", body:"Перевірити оновлення:
• brew upgrade swiftformat swiftlint periphery
• Перевірити GitHub Actions
• Оновити Xcode якщо потрібно", due date:(current date) + 30 * days}
    end tell
end tell
EOF

if [ $? -eq 0 ]; then
    echo "✅ Створено нагадування: Оновлення залежностей (щомісяця)"
else
    echo "⚠️  Не вдалося створити нагадування."
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  📱 Нагадування створені в додатку Reminders!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Розклад:"
echo "  • Щотижня: Перевірка невикористаного коду"
echo "  • Щомісяця: Повний аудит коду"
echo "  • Щомісяця: Оновлення залежностей"
echo ""
echo "  💡 Відкрийте Reminders щоб налаштувати повторення"
echo ""
