---
name: diagnose-systemeq-wiring
description: "Diagnose SystemEQ features that appear connected but have no effect: a setting persists without changing behavior, preset or EQ state is not restored, device selection silently refuses, or startup differs between normal and login-item launch. Also use to adversarially re-check fixes for these symptoms. Do not use for crashes, audio quality, performance, visual layout, or compiler errors."
---

# Діагностика мертвої проводки

Виконувати лише релевантні кроки. Не читати всі журнали й нотатки за замовчуванням.

## 1. Відокремити спостереження від причини

Зафіксувати точну дію, очікуваний ефект, конфігурацію Debug/Release і час події. Для Release за потреби читати:

```bash
/usr/bin/log show --predicate 'subsystem == "com.denzam.SystemEQ"' --last 30m --style compact
```

У Release unified log містить лише `warning`/`error`; у Debug `dlog` пише в консоль Xcode. Час процесу звіряти вузько:

```bash
ps -axo pid,lstart,command | rg 'SystemEQ for Mac|ProjectMHelper'
```

## 2. Простежити шлях до ефекту

Шукати ключ або API через `rg`, потім пройти ланцюг `контрол → запис → читання → побічний ефект`:

```bash
rg -n 'settingKey|sideEffectAPI' 'SystemEQ for Mac' --glob '*.swift'
```

Оголошення `@AppStorage` і binding не є споживачем ефекту. Перевірити guard-и та помилки, які лише логуються й не показуються в UI.

## 3. Перевірити життєвий цикл і узгодженість

- Після відкладеного `DispatchQueue.main.async` не читати похідний стан у тому самому такті. Орієнтир: `AudioEngine.bandMode → bands`.
- Стартова логіка має виконуватися без вікна. Орієнтир: `AppStartup.run()` з `applicationDidFinishLaunching`.
- Невдале відновлення не має стирати намір користувача. Орієнтир: `setEnabled(_:persistState:)`.
- Перед тестами persistence перевірити інʼєкцію ізольованого `UserDefaults`; орієнтир: `PresetPersistence.defaults`.

## 4. Спробувати спростувати виправлення

Сформулювати інваріант і хоча б один контрприклад із різними значеннями, але однаковою «ідентичністю». Перевірити не лише зберігання стану, а й реальний side effect. Додати регресійний тест, що падає без виправлення, та пройти позитивний і негативний сценарії.

Після тестів перечитати фінальний diff у свіжому проході. Розділити висновки на `підтверджено кодом/тестом` і `гіпотеза для ручного відтворення`; не призначати високий пріоритет без доведеного шляху.

## Obsidian — лише за потреби

Не завантажувати волт автоматично. Якщо індекс існує й клас проблеми повторюється або користувач просить попередні уроки, шукати лише в ньому:

```bash
rg -n -i 'ключові слова' "$HOME/Documents/DevNotes/000 Уроки розробки — покажчик.md"
```

Прочитати максимум дві релевантні нотатки за wikilink. Репозиторій є джерелом правди про поточний SystemEQ; волт містить лише переносні уроки.

Для перевірки дозволів або login item не перезбирати застосунок між увімкненням і перезапуском: зміна ad-hoc збірки змінює її ідентичність для macOS.
