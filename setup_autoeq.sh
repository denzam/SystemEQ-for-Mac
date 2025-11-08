#!/bin/bash
# Скрипт для встановлення AutoEQ та залежностей

echo "Setting up AutoEQ Local Server..."

# Перевіряємо наявність Python 3
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

echo "Python 3 found: $(python3 --version)"

# Створюємо віртуальне середовище
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Активуємо віртуальне середовище
source venv/bin/activate

# Встановлюємо залежності
echo "Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Клонуємо AutoEQ репозиторій якщо його немає
if [ ! -d "AutoEq" ]; then
    echo "Cloning AutoEq repository..."
    git clone https://github.com/jaakkopasanen/AutoEq.git
fi

echo "Setup complete!"
echo "To start the server, run: ./start_server.sh"
