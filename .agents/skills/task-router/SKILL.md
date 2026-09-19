---
name: task-router
description: "Local, zero-key task complexity and risk classifier. Evaluates user tasks and git changes to assign model tiers (flash_lite, flash, pro), risk levels (low, medium, critical), and execution strategies (direct, review, plan_required). Reusable across projects."
---

# Task Router — Локальний класифікатор задач і ризиків

Швидкий (5 мс), детерміністичний інструмент прийняття рішень (System 1) без використання зовнішніх API-ключів чи сторонніх сервісів. Запобігає галюцинаціям, випадковим правкам критичних зон коду та заощаджує токени.

---

## 1. Коли використовувати

- **Перед внесенням змін до коду:** запустити роутер для визначення рівня ризику задачі.
- **Перед делегуванням субагенту (`invoke_subagent`):** визначити оптимальний рівень моделі (`flash_lite`, `flash`, `pro`).
- **Перед початком рефакторингу чи виправлення багів:** перевірити, чи потрібен повноцінний план реалізації (`plan_required`).

---

## 2. Як запускати

Скрипт знаходиться в папці скіла:

```bash
# 1. Швидка перевірка за промптом і поточним git status (повертає чистий JSON):
python3 .agents/skills/task-router/scripts/route.py "текст задачі або опис змін"

# 2. Перевірка конкретних файлів:
python3 .agents/skills/task-router/scripts/route.py --files "Audio/CoreAudioEngine.swift"

# 3. Перевірка лише за текстом без огляду на git:
python3 .agents/skills/task-router/scripts/route.py "виправити одрук у документації" --no-git

# 4. Читабельний вивід для людини:
python3 .agents/skills/task-router/scripts/route.py "рефакторинг аудіо-буфера" --pretty
```

---

## 3. Матриця рішень та дії агента

| Рівень (`tier`) | Ризик (`risk`) | Стратегія (`strategy`) | Дія для Antigravity | Дія для Codex / Claude Code |
|---|---|---|---|---|
| **`flash_lite`** | `low` | `direct` | Виконувати правку одразу без планування | Робити правку одразу (швидкий режим) |
| **`flash`** | `medium` | `review` | Звичайний режим розробки; при делегуванні — модель `flash` | Виконати зміни та запустити тести/валідацію |
| **`pro`** | `critical` | `plan_required` | **Обов'язковий Planning Mode** (`implementation_plan.md`) перед будь-якими змінами; при делегуванні — модель `pro` | Зупинитися, скласти покроковий план і погодити з користувачем |

---

## 4. Кастомізація під інші проєкти

Скіл повністю універсальний і переноситься в будь-який інший проєкт простим копіюванням папки `task-router/` у `.agents/skills/`.

За потреби в корені будь-якого проєкту можна створити необов'язковий файл конфігурації `.task-router.json`:

```json
{
  "critical_paths": [
    "Audio/",
    "CoreAudio",
    "Kernel/",
    "Security/",
    "crypto"
  ],
  "low_paths": [
    "\\.md$",
    "\\.json$",
    "Docs/",
    "Assets/"
  ],
  "critical_keywords": [
    "\\barchitecture\\b",
    "\\bhot path\\b",
    "\\bmemory leak\\b"
  ],
  "low_keywords": [
    "\\btypo\\b",
    "\\breadme\\b",
    "\\bпереклад\\b"
  ]
}
```

Якщо конфіг відсутній, роутер використовує вбудовані розумні евристики для виявлення критичних компонентів (CoreAudio, hot-path, багатопоточність, безпека).
