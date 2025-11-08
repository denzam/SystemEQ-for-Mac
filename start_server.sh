#!/bin/bash
# Скрипт для запуску AutoEQ Local Server

# Визначаємо абсолютний шлях до директорії проекту
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Активуємо віртуальне середовище
source "$SCRIPT_DIR/venv/bin/activate"

# Запускаємо сервер
python3 "$SCRIPT_DIR/autoeq_server.py"
