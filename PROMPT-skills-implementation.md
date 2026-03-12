# Промпт: реализация системы навыков (skills) в ai-inst

## Контекст проекта

**ai-inst** — CLI-инструмент (bash) + MCP-сервер (TypeScript) для управления модульными инструкциями AI-агентов.

Архитектура "два репозитория":
- **Tool repo** (`/home/moonbreeze/ai-inst/`) — сам инструмент: CLI `ai-inst`, MCP-сервер `mcp-server/`, тесты `tests/`
- **Rules repo** (`~/.ai-instructions/`) — пользовательские модули в `modules/`, версионируется git

Текущий поток: модули (markdown-файлы) конкатенируются при `ai-inst build` в целевые файлы (CLAUDE.md, .cursorrules, AGENTS.md), которые целиком загружаются в контекст агента.

### Файлы проекта

- `ai-inst` (906 строк) — основной CLI на bash
- `mcp-server/src/index.ts` (155 строк) — MCP-сервер, оборачивающий CLI
- `tests/test_cli.sh` (678 строк) — тесты CLI
- `install.sh` — установщик
- `README.md` — документация

### Текущая конфигурация проекта (`.ai-modules`)

```
# Modules for this project (one per line)
targets: CLAUDE.md .cursorrules AGENTS.md

common
lang-python
framework-fastapi
```

Модули хранятся как плоские markdown-файлы: `~/.ai-instructions/modules/<name>.md`

---

## Задача

Добавить в ai-inst систему **навыков (skills)** — инструкций, которые загружаются агентом **по запросу**, а не всегда присутствуют в контексте. Это решает проблему разрастания контекста по мере роста количества управляемых инструкций.

Навыки следуют открытому стандарту **Agent Skills** (https://agentskills.io), который поддерживается всеми основными платформами.

---

## Стандарт Agent Skills — формат SKILL.md

Каждый навык — это директория с обязательным файлом `SKILL.md` и опциональными ресурсами:

```
my-skill/
├── SKILL.md           # обязательно — инструкции с YAML frontmatter
├── scripts/           # опционально — скрипты для выполнения
├── references/        # опционально — справочная документация
├── examples/          # опционально — примеры
└── assets/            # опционально — шаблоны, конфиги, изображения
```

### Формат SKILL.md

```yaml
---
name: skill-name
description: Описание — когда и зачем использовать навык
---

Инструкции для агента (markdown).
```

Поля frontmatter:
- `name` (рекомендуется) — идентификатор, lowercase + hyphens, макс 64 символа. Если не указан — берётся имя директории.
- `description` (рекомендуется) — описание для progressive disclosure. Агент видит только description при загрузке, полный контент — при вызове.

Дополнительные поля (специфичны для платформ, ai-inst их **сохраняет as-is**, не интерпретирует):
- `disable-model-invocation` — запрет авто-вызова (Claude Code, Cursor)
- `user-invocable` — скрыть из меню пользователя (Claude Code)
- `allowed-tools` — ограничение инструментов (Claude Code)
- `context` — запуск в субагенте (Claude Code)
- `allow_implicit_invocation` — Codex-аналог disable-model-invocation

---

## Куда платформы ищут навыки

| Платформа | Проектный путь | Глобальный путь |
|-----------|---------------|-----------------|
| **Claude Code** | `.claude/skills/<name>/` | `~/.claude/skills/<name>/` |
| **Codex** | `.agents/skills/<name>/` | `~/.agents/skills/<name>/` |
| **Cursor** | `.agents/skills/<name>/`, `.cursor/skills/<name>/`, `.claude/skills/<name>/` | `~/.cursor/skills/<name>/` |
| **Roo Code** | `.agents/skills/<name>/`, `.roo/skills/<name>/` | `~/.agents/skills/<name>/`, `~/.roo/skills/<name>/` |
| **Windsurf** | `.agents/skills/<name>/`, `.windsurf/skills/<name>/`, `.claude/skills/<name>/` | `~/.agents/skills/<name>/` |

**Вывод**: `.agents/skills/` — универсальный путь (Codex, Cursor, Roo, Windsurf). `.claude/skills/` — для Claude Code (также читается Cursor, Windsurf). Оба пути нужны для полного покрытия.

---

## Дизайн решения

### 1. Хранилище навыков в rules repo

```
~/.ai-instructions/
├── modules/              # как сейчас — всегда в контексте
│   ├── common.md
│   └── lang-python.md
└── skills/               # НОВОЕ — по запросу
    ├── deploy/
    │   ├── SKILL.md
    │   └── scripts/
    │       └── deploy.sh
    ├── refactor/
    │   └── SKILL.md
    └── db-migrate/
        ├── SKILL.md
        └── references/
            └── schema.md
```

Навыки хранятся как директории в `~/.ai-instructions/skills/`. Формат полностью соответствует стандарту Agent Skills — `SKILL.md` с frontmatter + опциональные поддиректории.

### 2. Конфигурация проекта (`.ai-modules`)

Расширить формат секцией `[skills]`:

```ini
# Modules (always in context)
targets: CLAUDE.md
common
lang-python

# Skills (loaded on demand)
[skills]
deploy
refactor
db-migrate
```

Парсер `parse_ai_modules` должен быть расширен для поддержки секции `[skills]`. До `[skills]` — модули (как сейчас). После `[skills]` — навыки. Вывод парсера добавляет переменную `SKILLS`.

### 3. Новые CLI-команды

#### Управление навыками (зеркалит модули)

```bash
ai-inst skill list                    # Список навыков (* = активен в проекте)
ai-inst skill new <name>              # Создать навык (директория + SKILL.md)
ai-inst skill edit <name>             # Редактировать SKILL.md в $EDITOR
ai-inst skill show <name>             # Показать содержимое SKILL.md
ai-inst skill rm <name>               # Удалить навык
```

#### Управление навыками проекта

```bash
ai-inst project add-skill <name...>   # Добавить навыки в секцию [skills]
ai-inst project rm-skill <name...>    # Убрать навыки из секции [skills]
```

#### Детали реализации команд

**`skill new <name>`**:
- Создаёт `$SKILLS_DIR/<name>/SKILL.md` с шаблоном:
  ```yaml
  ---
  name: <name>
  description:
  ---

  # <name>

  <!-- Add skill instructions here -->
  ```
- Открывает в `$EDITOR` если задан
- Коммитит в rules repo

**`skill list`**:
- Итерирует по директориям в `$SKILLS_DIR/`
- Проверяет наличие `SKILL.md` в каждой
- Помечает `*` если навык есть в текущем проекте (секция `[skills]` в `.ai-modules`)

**`skill show <name>`**:
- Выводит содержимое `$SKILLS_DIR/<name>/SKILL.md`

**`skill edit <name>`**:
- Открывает `$SKILLS_DIR/<name>/SKILL.md` в `$EDITOR`
- Коммитит после редактирования

**`skill rm <name>`**:
- Удаляет директорию `$SKILLS_DIR/<name>/` целиком
- Коммитит

**`project add-skill <name...>`**:
- Проверяет что навык существует в rules repo
- Добавляет имя в секцию `[skills]` файла `.ai-modules`
- Если секции `[skills]` нет — создаёт её в конце файла

**`project rm-skill <name...>`**:
- Удаляет имя из секции `[skills]` файла `.ai-modules`

### 4. Расширение сборки (`cmd_build`)

Команда `ai-inst build` должна быть расширена:

#### 4.1. Модули — без изменений
Конкатенация модулей → целевые файлы (CLAUDE.md и др.) — как сейчас.

#### 4.2. Навыки — копирование в директории платформ

Для каждого навыка из секции `[skills]`:

1. **Копировать директорию навыка** в два пути проекта:
   - `.claude/skills/<name>/` — для Claude Code (+ Cursor, Windsurf читают этот путь)
   - `.agents/skills/<name>/` — для Codex, Cursor, Roo Code, Windsurf

2. **Не трансформировать** содержимое — формат SKILL.md одинаков для всех платформ. Копировать as-is всю директорию навыка (SKILL.md + scripts/ + references/ + всё остальное).

3. **Генерировать индекс навыков** в целевых файлах (CLAUDE.md и др.) — блок в конце сборки, перед local instructions:
   ```markdown
   ## Available skills

   The following skills are available on demand:
   - `deploy` — Deploy the application to production
   - `refactor` — Refactor code following best practices
   - `db-migrate` — Database migration procedures
   ```
   Description для индекса извлекается из frontmatter каждого SKILL.md.

#### 4.3. Обновление .gitignore

При сборке навыков добавлять в `.gitignore`:
```
.claude/skills/
.agents/skills/
```
Эти директории авто-генерируются, их не нужно коммитить в проект.

#### 4.4. Очистка

Перед копированием навыков удалять старое содержимое `.claude/skills/` и `.agents/skills/`, чтобы убранные из проекта навыки не оставались.

### 5. Расширение MCP-сервера

Добавить в `mcp-server/src/index.ts` инструменты:

```typescript
// Навыки
server.tool("list_skills", ...)           // ai-inst skill list
server.tool("read_skill", ...)            // ai-inst skill show <name>
server.tool("create_skill", ...)          // создание навыка
server.tool("update_skill", ...)          // обновление SKILL.md
server.tool("delete_skill", ...)          // ai-inst skill rm <name>

// Навыки проекта
server.tool("add_project_skill", ...)     // ai-inst project add-skill <name...>
server.tool("remove_project_skill", ...)  // ai-inst project rm-skill <name...>
```

Инструменты `create_skill` и `update_skill` работают аналогично `create_module` / `update_module` — принимают `name` и `content`, пишут в SKILL.md, коммитят.

### 6. Тесты

Добавить в `tests/test_cli.sh` новую секцию тестов. Следовать существующему стилю (helper-функции `init_repo`, `create_module`, `assert_*`).

Добавить helper:
```bash
create_skill() {
  local name="$1"
  local description="${2:-Test skill}"
  local content="${3:-Skill instructions for $name}"
  mkdir -p "$AI_INST_DIR/skills/$name"
  cat > "$AI_INST_DIR/skills/$name/SKILL.md" << EOF
---
name: $name
description: $description
---

$content
EOF
  cd "$AI_INST_DIR" && git add -A && git commit -m "add skill $name" >/dev/null 2>&1 && cd - >/dev/null
}
```

#### Тесты навыков (skill):

```
test_skill_new            — создание навыка, проверка директории и SKILL.md
test_skill_new_duplicate  — ошибка при дубликате
test_skill_show           — вывод содержимого SKILL.md
test_skill_show_missing   — ошибка при несуществующем
test_skill_rm             — удаление директории навыка
test_skill_list           — список навыков
test_skill_list_with_project_markers — маркеры * для активных в проекте
```

#### Тесты проекта с навыками:

```
test_project_add_skill          — добавление навыка в [skills]
test_project_add_skill_creates_section — создание секции [skills] если нет
test_project_add_skill_duplicate — дубликат
test_project_rm_skill           — удаление из [skills]
```

#### Тесты сборки с навыками:

```
test_build_copies_skills_to_claude_dir  — навыки в .claude/skills/
test_build_copies_skills_to_agents_dir  — навыки в .agents/skills/
test_build_skill_directory_structure    — SKILL.md + ресурсы скопированы
test_build_skills_index_in_target       — индекс навыков в CLAUDE.md
test_build_cleans_old_skills            — удаление старых навыков при пересборке
test_build_updates_gitignore_for_skills — .gitignore обновлён
test_build_missing_skill_warning        — предупреждение о несуществующем навыке
```

#### Тесты MCP (опционально, если время позволяет):

Достаточно убедиться, что новые CLI-команды существуют и корректно вызываются — MCP-сервер их просто оборачивает.

### 7. Обновление help и README

#### `cmd_help()` — добавить секции:

```
Skills:
  skill list                     List skills (* = active in project)
  skill new <name>               Create skill
  skill edit <name>              Edit skill
  skill show <name>              Show skill content
  skill rm <name>                Delete skill
```

Обновить секцию Project:
```
Project:
  project init                    Create .ai-modules + instructions.local.md
  project add <mod...>            Add modules to project
  project rm <mod...>             Remove modules from project
  project add-skill <skill...>    Add skills to project
  project rm-skill <skill...>     Remove skills from project
  project edit                    Edit local instructions
  project status                  Show project status
  project targets <file...>       Set target files
```

#### README.md — добавить:
- Описание навыков в секции Architecture
- Примеры использования в Quick Start
- Справку по командам skill

### 8. Обновление `repo init`

При `ai-inst repo init` создавать `$AI_INST_DIR/skills/` наряду с `$AI_INST_DIR/modules/`.

---

## Переменные и константы

Добавить в начало CLI-скрипта:

```bash
SKILLS_DIR="$AI_INST_DIR/skills"
```

---

## Парсинг `.ai-modules` — обновлённый `parse_ai_modules`

Логика:
- Строки до `[skills]` — модули (как сейчас)
- Строки после `[skills]` — навыки
- `targets:` может быть в любом месте
- Комментарии (`#`) и пустые строки игнорируются

Вывод функции должен включать три переменные:
```bash
echo "TARGETS='${targets[*]}'"
echo "MODULES='${modules[*]}'"
echo "SKILLS='${skills[*]}'"
```

---

## Извлечение description из SKILL.md

Нужна helper-функция для извлечения `description` из YAML frontmatter:

```bash
skill_description() {
  local skill_md="$SKILLS_DIR/$1/SKILL.md"
  [[ -f "$skill_md" ]] || return
  # Простой парсинг: найти строку "description: ..." между первыми "---"
  sed -n '/^---$/,/^---$/{ /^description:/{ s/^description: *//; s/^ *"//; s/" *$//; p; q; } }' "$skill_md"
}
```

---

## Порядок реализации

1. Переменные и helpers (`SKILLS_DIR`, `skill_path`, `skill_exists`, `skill_description`, `parse_ai_modules` обновление)
2. Команды skill (new, list, show, edit, rm)
3. Команды project (add-skill, rm-skill) + обновление project status
4. Сборка (build) — копирование навыков + индекс + .gitignore + очистка
5. Обновление repo init
6. MCP-сервер — новые инструменты
7. Тесты
8. Help и README

---

## Важные ограничения

- **Не ломать существующую функциональность**. Все текущие тесты (55 штук) должны проходить.
- **Формат `.ai-modules` обратно совместим**. Файл без секции `[skills]` работает как раньше.
- **SKILL.md не трансформируется** — копируется as-is. ai-inst не интерпретирует платформо-специфичные поля frontmatter.
- **Навыки с ресурсами** — вся директория навыка копируется целиком (не только SKILL.md).
- **Стиль кода** — следовать существующему стилю: bash-функции с префиксом `cmd_`, helpers вверху, `die`/`info` для сообщений, `ensure_*` для проверок.
- **Тесты** — следовать стилю test_cli.sh: функции `test_*`, helper `create_skill`, использовать `assert_*` функции.
- **Версию не менять** — оставить `VERSION="0.1.0"`.

---

## Запуск тестов

```bash
bash tests/test_cli.sh
```

После реализации все тесты (старые + новые) должны проходить.
