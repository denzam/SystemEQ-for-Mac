# Homebrew Cask для SystemEQ for Mac

## Для користувачів

### Встановлення
```bash
brew trust denzam/systemeq
brew install --cask denzam/systemeq/systemeq
```

Починаючи з Homebrew 6.0, сторонні тапи треба явно позначити довіреними —
без `brew trust` встановлення падає з `Refusing to load cask ... from
untrusted tap`. Робиться один раз на кожному Mac; на Homebrew 5 і старіших
цієї команди немає, тому її пропускають.

Офіційні релізи від v1.4.6 містять застосунок із підписом Developer ID та
нотаризацією Apple; DMG також підписаний і нотаризований. Знімати quarantine
не потрібно. BlackHole потрібен на macOS 13–14.3, для резервного маршруту або
ручного режиму BlackHole; на macOS 14.4+ рекомендований backend — Automatic.

### Оновлення
```bash
brew upgrade --cask systemeq
```

### Видалення
```bash
brew uninstall --cask systemeq
```

---

## Для розробника

Чинний cask міститься в [denzam/homebrew-systemeq](https://github.com/denzam/homebrew-systemeq/blob/main/Casks/systemeq.rb).
Після успішної публікації релізний workflow автоматично оновлює в ньому
версію та SHA256 опублікованого DMG. Окреме ручне копіювання не потрібне.

`Casks/systemeq.rb` у цьому репозиторії — довідкова копія для v1.4.6;
для встановлення й перевірки поточної версії використовуй чинний tap.
Не замінюй його cask старою довідковою копією. Перед будь-якою ручною зміною
звір версію та SHA256 з фактичним DMG відповідного GitHub-релізу.
