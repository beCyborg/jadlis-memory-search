---
name: memory-search
description: "Semantic search over the user's own notes (Obsidian vault folders indexed by local qmd) plus index maintenance: status, reindex, add or remove a folder, auto-reindex on/off. Always sends typed lex + vec sub-queries with intent and rerank:false; reads hits via get. Use before creating a new note to check for duplicates. Triggers: search my notes, where did I write about, what did I decide on, find in my vault, memory search, reindex notes. RU triggers: найди в заметках, где я писал про, что я решил о, поищи в хранилище, поиск по смыслу, было ли у меня про, в моих заметках, есть ли уже заметка, переиндексируй заметки, статус поиска. Do NOT use for: web search → /search; exact string, file name or path → Grep; first-time setup → /memory-search-setup."
argument-hint: "<вопрос> | status | reindex [--full|--cleanup] | add <папка> | remove <коллекция> | autoindex on|off|status"
allowed-tools:
  - mcp__plugin_jadlis-memory-search_qmd__query
  - mcp__plugin_jadlis-memory-search_qmd__get
  - mcp__plugin_jadlis-memory-search_qmd__multi_get
  - mcp__plugin_jadlis-memory-search_qmd__status
  - Read
  - Grep
  - Glob
  - AskUserQuestion
  - Bash(qmd status*)
  - Bash(qmd collection list*)
  - Bash(qmd collection add *)
  - Bash(qmd context *)
  - Bash(qmd cleanup --dry-run*)
  - Bash(launchctl print gui/*)
  - Bash(grep -rIl *)
  - Bash(command grep -rIl *)
  - Bash(node "${CLAUDE_PLUGIN_ROOT}/scripts/inventory.mjs" *)
  - Bash(JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/*)
---

# memory-search — поиск по смыслу в заметках

`$ARGUMENTS`

Инструменты: `mcp__plugin_jadlis-memory-search_qmd__{query,get,multi_get,status}` (отложены → `ToolSearch` с `+jadlis-memory-search`). Грабли qmd с причинами — `${CLAUDE_PLUGIN_ROOT}/skills/memory-search/references/gotchas.md`; прочитай при пустой или странной выдаче и перед `reindex --full`.

Скрипты плагина — только так: `JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/<скрипт>" …`.

| Аргумент | Режим |
|---|---|
| любой текст | вопрос → § Запрос |
| `status` | § Статус |
| `reindex [--full\|--cleanup]` | § Переиндексация |
| `add <папка>` / `remove <коллекция>` | § Коллекции |
| `autoindex on\|off\|status` | § Автообновление |

Инструментов нет или `status` отвечает ошибкой → «плагин не настроен или сессия стартовала до установки qmd: запусти `/memory-search-setup`, затем перезапусти Claude Code». Стоп.

## Запрос

Первым вызовом в сессии — `status`: коллекции, их описания (context) и пути. По описаниям выбери коллекции; тема явная → `collections`, неясная → без фильтра.

Шаблон — **всегда typed**, plain `query` запрещён (уходит в автоэкспансию и реранк: медленно, для русского ненадёжно):

```json
{"searches":[{"type":"lex","query":"<леммы/основы: переезд квартир аренд>"},
             {"type":"vec","query":"<вопрос полным предложением на языке заметок>"}],
 "intent":"<что ищем и зачем — одна фраза>",
 "collections":["<slug>"], "limit":6, "rerank":false}
```

- `intent` обязателен: он уточняет выдачу и сниппеты. `rerank:false` всегда (реранк = +10 с и +610 МБ модели ради пары процентов точности). `limit` 5–8.
- Первый подзапрос весит ×2: конкретные слова и названия → `lex` первым; размытое «что я думал о…» → `vec` первым.
- **lex (BM25, FTS5)**: русского стеммера нет, работает префикс. Пиши леммы или основы без окончаний: `ипотек` найдёт «ипотека/ипотеки/ипотеку», а `ипотеку` не найдёт «ипотека». Основы короче 4 букв шумят. Фразы — в кавычках (`"план питания"`), исключение — `-слово`. Английские слова — в базовой форме.
- **vec**: одно полное предложение на языке заметок. Vault смешанный (RU + EN) → вторая `vec`-строка на другом языке.
- **hyde** — только если lex + vec промахнулись: 2–3 предложения вида «заметка, которая отвечает на <вопрос>: …».
- Хвосты длинных заметок и ячейки таблиц вектор часто не видит (чанки усечены) — ищи там через `lex`.
- Точная строка, идентификатор, имя файла, путь → Grep по папке коллекции, не qmd.

Пусто или мимо — по лестнице, прежде чем сказать «не нашёл»:
1. `lex` короче: основы вместо слов, синонимы, английский вариант термина.
2. Убрать `collections` — тема может лежать в соседней коллекции.
3. Добавить `hyde`.
4. Grep по ключевому слову в путях коллекций (`command grep -rIl`, если Grep-инструмент молчит из-за `.gitignore`).
5. Заметка создана меньше минуты назад → индекс ещё не догнал; предложить `/memory-search reindex`.

### Чтение найденного

- `get` с `file` = `qmd://<slug>/<путь>` или `#docid` из выдачи. Нужен кусок — суффикс `:строка:сколько` или `fromLine = max(1, line − 20)`, `maxLines = 80` (поле `line` есть у каждого результата).
- `multi_get` — до 5 файлов за вызов (список через запятую или `#docid`), с `maxLines`.
- Больше 3 заметок целиком в ответ не вываливать — сначала список, потом спросить, что раскрыть.

### Ответ

Коротко: по строке на находку — заголовок, `<slug>/<путь>`, одной фразой, почему она подходит (из сниппета или прочитанного куска). Потом — ответ на вопрос по прочитанному, со ссылкой на заметку. Ничего не нашлось после лестницы → так и сказать, перечислив, что пробовал.

## Дедуп перед новой заметкой

Перед созданием заметки на тему X — в таком порядке:
1. `query` с `lex` + `vec` по теме X, `limit` 8.
2. Grep по ключевой строке (точное название, идентификатор) в папках коллекций.
3. Только если оба пусты — создавать. Нашлось похожее → показать и спросить: дописать туда или всё же новую.

## Статус

```bash
qmd status
qmd collection list
JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-launchd.sh" --data "${CLAUDE_PLUGIN_DATA}" --status
JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/show-log.sh" reindex 5
```

Плюс MCP `status`. Одна таблица:

| Что | Значение |
|---|---|
| Коллекции | slug → путь, заметок (MCP `status`) |
| Индекс | Total / Vectors / pending (`qmd status`) |
| Последняя переиндексация | время и итог (хвост `reindex.log`) |
| Автообновление | `state = running` / не установлен (код 3) / Linux — хук + crontab |
| Poller | возраст `watch.alive` и последние строки `watch.log` (из `--status`) |

Коллекция есть в `qmd collection list`, но её нет в MCP `status` (или наоборот) → «MCP-сервер видит старый список — перезапусти Claude Code». Pending > 0 и poller не жив → предложить `reindex`.

## Переиндексация

- `reindex` → `JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/qmd-reindex.sh" manual`. Больше 300 заметок (по MCP `status`) → `run_in_background: true`. Вывод — одна строка итога; `уже идёт переиндексация` — не ошибка.
- `reindex --full` → пересчитать все векторы (после смены модели или подозрения на мусорные векторы). Сказать, что это минуты–десятки минут и векторный поиск до конца будет неполным; только после «да», в фоне:

```bash
JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/qmd-reindex.sh" full
```

  Скрипт держит тот же lock и выставляет `QMD_EMBED_CONTEXT_SIZE=506`; голый `qmd embed -f` не запускать — без этой переменной длинные чанки дадут мусорные векторы без ошибки.
- `reindex --cleanup` (после правок и `--full` остаются осиротевшие векторы: Vectors > Total) → `qmd cleanup --dry-run`, показать, что уйдёт, и только после «да» — `qmd cleanup`.

## Коллекции

**`add <папка>`** — путь абсолютный или от корня vault (корень = общий родитель путей коллекций из MCP `status`; неочевиден — спросить).
1. `node "${CLAUDE_PLUGIN_ROOT}/scripts/inventory.mjs" "<vault>" --folder "<папка>" --titles 40 --samples 5 --tags 10 --json` — по этому выводу (файлы не читать) описание по правилам `${CLAUDE_PLUGIN_ROOT}/skills/memory-search-setup/references/inventory-rules.md` § Описания.
2. `node "${CLAUDE_PLUGIN_ROOT}/scripts/inventory.mjs" --slug "<папка>" --taken "<имена из qmd collection list>"`.
3. Показать «папка → slug, описание», подтверждение одной репликой.
4. `qmd collection add "<путь>" --name <slug>`, затем `qmd context add "qmd://<slug>/" "<описание>"`.
5. `qmd-reindex.sh manual` в фоне (как в § Переиндексация).
6. В `CLAUDE.md` есть секция «Поиск по смыслу» → предложить дописать строку коллекции.
7. «Перезапусти Claude Code — MCP-сервер увидит новую коллекцию только после перезапуска».

**`remove <коллекция>`** — сказать, что удалится только индекс, заметки останутся; после «да» — `qmd collection remove <коллекция>`, убрать её строку из секции «Поиск по смыслу» в `CLAUDE.md` (с согласия), напомнить про перезапуск.

## Автообновление

| Аргумент | Команда |
|---|---|
| `autoindex on` | `JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-launchd.sh" --data "${CLAUDE_PLUGIN_DATA}"` |
| `autoindex off` | то же с `--remove` |
| `autoindex status` | то же с `--status` |

Код 2 (не macOS) → показать напечатанную строку `@reboot …` для `crontab -e`; сам crontab не трогать. После `off` индекс догоняется только хуком при старте сессии. Перед удалением плагина — сначала `autoindex off`, иначе агент останется жить из папки данных.
