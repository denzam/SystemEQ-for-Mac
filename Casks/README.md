# Homebrew Cask для SystemEQ for Mac

## Для користувачів

### Встановлення
```bash
brew tap denyszamorniak/systemeq
brew install --cask systemeq
```

### Оновлення
```bash
brew upgrade --cask systemeq
```

### Видалення
```bash
brew uninstall --cask systemeq
```

---

## Для розробника (налаштування Homebrew Tap)

### Крок 1: Створити окремий репозиторій
Створіть репозиторій на GitHub з назвою `homebrew-systemeq`

### Крок 2: Додати формулу
```bash
git clone https://github.com/denyszamorniak/homebrew-systemeq.git
mkdir -p homebrew-systemeq/Casks
cp Casks/systemeq.rb homebrew-systemeq/Casks/
cd homebrew-systemeq
git add . && git commit -m "Add SystemEQ cask"
git push
```

### Крок 3: Оновлення при новому релізі
1. Оновити `version` в `systemeq.rb`
2. Оновити `sha256` (отримати: `shasum -a 256 SystemEQ-v*.dmg`)
3. Push в `homebrew-systemeq` репозиторій
