# Homebrew Cask для SystemEQ for Mac

## Для користувачів

### Встановлення
```bash
brew tap denzam/systemeq
brew trust denzam/systemeq
brew install --cask systemeq
```

Починаючи з Homebrew 6.0, сторонні тапи треба явно позначити довіреними —
без `brew trust` встановлення падає з `Refusing to load cask ... from
untrusted tap`. Робиться один раз на кожному Mac; на Homebrew 5 і старіших
цієї команди немає, тому її пропускають.

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
git clone https://github.com/denzam/homebrew-systemeq.git
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
