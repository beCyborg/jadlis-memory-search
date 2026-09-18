---
name: memory-search-setup
description: "Onboarding for jadlis-memory-search: checks node and qmd, finds the Obsidian vault, inventories its folders, proposes what to index, writes one-line folder descriptions, builds the local qmd index, installs auto-reindex (launchd on macOS, hook-only elsewhere), merges permissions and a CLAUDE.md hint with consent. Run once after install; again to re-pick folders or rewrite descriptions. Triggers: set up memory search, index my notes, memory-search-setup, connect my vault to search. RU triggers: настрой поиск по заметкам, проиндексируй заметки, подключи хранилище к поиску, настрой поиск по смыслу, пересобери список папок, перепиши описания папок. Do NOT use for: searching notes → /memory-search; add or remove one folder after setup → /memory-search add|remove; reindex or status → /memory-search."
argument-hint: "[--recheck] [--contexts] [--autoindex] [--auto] [--no-launchd]"
allowed-tools:
  - Read
  - Edit
  - Write
  - Glob
  - AskUserQuestion
  - Bash(ls *)
  - Bash(qmd collection list*)
  - Bash(qmd collection add *)
  - Bash(qmd context *)
  - Bash(qmd status*)
  - Bash(qmd search *)
  - Bash(qmd query *)
  - mcp__plugin_jadlis-memory-search_qmd__status
  - Bash(node "${CLAUDE_PLUGIN_ROOT}/scripts/inventory.mjs" *)
  - Bash(JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/*)
---

# memory-search-setup — онбординг поиска по смыслу

`$ARGUMENTS`

Скрипты: `${CLAUDE_PLUGIN_ROOT}/scripts/`. Правила инвентаря и описаний: `${CLAUDE_PLUGIN_ROOT}/skills/memory-search-setup/references/inventory-rules.md` — прочитай перед шагом 3.
Шаблоны: `${CLAUDE_PLUGIN_ROOT}/skills/memory-search-setup/assets/`. Данные плагина: `${CLAUDE_PLUGIN_DATA}`.

Скрипты плагина вызывай **только** так (переменных `CLAUDE_PLUGIN_*` в окружении Bash нет):
`JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/<скрипт>" …` и `node "${CLAUDE_PLUGIN_ROOT}/scripts/inventory.mjs" …`.

| Аргумент | Что делает |
|---|---|
| без аргумента | полный онбординг, шаги 1–11 |
| `--recheck` | шаги 1, 3, 4 по текущему списку коллекций → новые папки проходят 5–7, снятые — удаление с согласия → 11 |
| `--contexts` | только описания: шаг 5 для существующих коллекций → `qmd context add` → показать YAML |
| `--autoindex` | только шаг 8 |
| `--auto` | без вопросов (установщик, смоук) — правила ниже |
| `--no-launchd` | шаг 8 без вопроса: режим «только хук» |

**Ничего не писать на диск до шага 6.** Прерван раньше — в системе не должно остаться следов. `qmd init` **не вызывать никогда**: он кладёт индекс внутрь vault, и тот уезжает в синк.

**Режим `--auto`:** vault — `pwd` (или его родитель), если там есть `.obsidian/`; иначе первый открытый из `obsidian.json`; иначе FAIL и стоп; папки — все кандидаты без `skip`, кроме `huge` (их в таблицу как SKIPPED «огромная — выбери подпапки вручную»); описания пишутся без подтверждения; сборка в foreground; launchd ставится, если нет `--no-launchd`; шаги 9 и 10 не пишут ничего — строки SKIPPED в итоговой таблице; нет qmd → FAIL и стоп (ставить без согласия нельзя); чужие коллекции не трогать, свои добавлять рядом.

## Шаг 1 — предпосылки

Одна команда, **ровно в таком виде** (без `;`, `&&` и добавок — иначе она не попадёт под разрешения скилла):

```bash
JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh"
```

Выдаёт строки `os`, `node` (`ok` / `TOO_OLD` / `MISSING`), `qmd`, `disk_free`, `models_cached`, `qmd_config`, `collections` (вывод `qmd collection list` и пути), `vaults` (хранилища из `obsidian.json`, `(open)` — открытое), `local_qmd` (каждая найденная `.qmd/` вверх от `pwd`), `cwd_vault` (хранилище, в котором запущен Claude Code, или `none`). Шагу 2 этот вывод заменяет поиск хранилищ.

- `node` нет или мажор < 22 → macOS: `brew install node`; Linux: пакет дистрибутива или nvm. Сказать и **стоп** — без Node 22 qmd не работает.
- `qmd` нет → спросить согласие и выполнить `npm install -g @tobilu/qmd` (в `--auto` — FAIL и стоп). После установки MCP-сервер этой сессии всё равно мёртв — перезапуск в финале обязателен.
- Свободно < 2 ГБ → предупредить. Сказать, что скачается: модель эмбеддингов ~320 МБ в `~/.cache/qmd/models` при первой сборке. Реранкер (610 МБ) и генератор запросов (1,2 ГБ) **не нужны** — скилл поиска их не вызывает.
- `os` содержит `x86_64` → «первая сборка на Intel заметно дольше». `os` начинается с `Linux` → автообновление только хуком + строка для crontab (шаг 8).
- Уже есть коллекции (`qmd collection list`) → показать их списком и спросить `AskUserQuestion`: «Добавить мои папки рядом — твои коллекции не трогаю» / «Пропустить выбор папок — только автообновление, права и проверка». Предупредить: хук и poller плагина переиндексируют **все** коллекции из `index.yml`, включая твои; если у тебя уже подключён свой MCP-сервер qmd — выключи один из двух, иначе инструменты дублируются.
- Есть строка `local_qmd` (или `.qmd/` нашлась в выбранном на шаге 2 хранилище: `preflight.sh "<vault>"`) → **стоп с объяснением**: qmd, запущенный изнутри такой папки, берёт локальный `.qmd/index.yml` вместо общего конфига — индекс раздвоится и уедет в синк. Попросить перенести `.qmd/` из хранилища самому и перезапустить онбординг. Сами не удаляем.

Путь конфига qmd для шагов 6 и 11: `$QMD_CONFIG_DIR` > `$XDG_CONFIG_HOME/qmd` > `~/.config/qmd`, файл `index.yml`.

## Шаг 2 — хранилище

Кандидаты — из вывода шага 1: `cwd_vault` (если не `none`) и строки `vaults`.
- ≤ 4 кандидата → `AskUserQuestion` «Какое хранилище индексировать?»: первым — хранилище из `pwd` с пометкой «(текущая папка)», затем открытое в Obsidian с пометкой «(открыто сейчас)»; свой путь — через «Other».
- > 4 → нумерованная таблица, ответ номером или путём.
- Ничего не нашлось → спросить путь к папке с заметками (Obsidian не обязателен — подойдёт любая папка с `.md`).

## Шаг 3 — инвентарь

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/inventory.mjs" "<vault>" --depth 1 --table
```

Показать обе таблицы как есть: кандидаты (папка, заметок, прочих файлов, МБ, последняя правка, три примера заголовков) и «пропущено автоматически» (служебная, вложения, шаблоны, пусто). Папки с флагом «огромная» (> 5000 заметок) остаются кандидатами, но с пометкой. Заметки целиком **не открывать** — только вывод скрипта.

## Шаг 4 — выбор папок и имена коллекций

- ≤ 4 кандидата → `AskUserQuestion` с `multiSelect: true`, по опции на папку (в описании — число заметок и примеры заголовков).
- > 4 → нумерованная таблица кандидатов; ответ списком номеров, «все» или «всё хранилище».
- «Огромная» папка выбрана → предложить подпапки из `inventory.mjs … --folder <папка>` (отдельная коллекция на крупную подпапку) или взять целиком с предупреждением о времени сборки.
- «Всё хранилище» → одна коллекция на корень vault, в `ignore` — пропущенные папки (`<папка>/**`).
- `--recheck`: папки, уже стоящие в индексе, помечены «(уже в индексе)». Снята такая → `qmd collection remove <slug>` только после отдельного «да» (удаляется индекс, заметки не трогаются).

Имя коллекции — одно на папку:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/inventory.mjs" --slug "<папка>" --taken "<уже занятые имена через запятую>"
```

Занятые = существующие коллекции + slug'и, выданные на этом шаге. Показать таблицу «папка → коллекция»; пользователь может переименовать (только `[a-zA-Z0-9_-]`).

## Шаг 5 — описания (context)

По каждой выбранной папке:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/inventory.mjs" "<vault>" --folder "<папка>" --titles 40 --samples 5 --tags 10 --json
```

Пиши описания **только по этому выводу** (заголовки, подпапки, отрывки, теги), файлы не читай. Правила — `references/inventory-rules.md` § Описания:
- одна фраза на языке заметок, ≤ 120 символов, вид «<что это>: <3–5 тем>»;
- подпапкам — свои описания, только если у папки ≥ 3 подпапок по ≥ 10 заметок;
- без имён людей, диагнозов, сумм, адресов — описания попадают в файлы и в каждый ответ поиска.

Таблица «коллекция / подпапка → описание» на подтверждение одной репликой (в `--auto` — сразу дальше). В `--contexts` сразу после подтверждения — `qmd context add` из шага 6, `Read` итогового YAML, конец.

## Шаг 6 — запись

Только здесь что-то появляется на диске.

```bash
qmd collection add "<vault>/<папка>" --name <slug>
qmd context add "qmd://<slug>/" "<описание папки>"
qmd context add "qmd://<slug>/<Подпапка>" "<описание подпапки>"
```

- `collection add` сразу строит полнотекстовый индекс (без векторов) — на большой папке это минуты.
- «already exists» → имя занято: новый slug с `--taken`, повторить. «already exists for this path» → папка уже в индексе под другим именем: не дублировать, отметить в таблице.
- `ignore` задаётся только в YAML: `Edit` файла `index.yml` → в блок коллекции `ignore:` со списком глобов. Флага CLI для этого нет.
- В конце `Read` `index.yml` и показать блоки новых коллекций.

## Шаг 7 — сборка векторов

```bash
JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/qmd-reindex.sh" setup --log "${CLAUDE_PLUGIN_DATA}/logs/setup-build.log"
```

Интерактивно — `run_in_background: true`; сказать «сборка идёт в фоне (первый раз качается модель ~320 МБ)» и идти к шагу 8, не ждать. В `--auto` — foreground, `timeout: 600000`. Вывод `уже идёт переиндексация` — не ошибка: сборку уже ведёт хук или poller, шаг 11 дождётся её.

## Шаг 8 — автообновление

`--no-launchd` → режим «только хук», без вопроса. Иначе на macOS — `AskUserQuestion` «Как обновлять индекс?»:
1. «launchd — следит за папками постоянно, правки видны через ~1–2 мин (рекомендую)»;
2. «Только хук — индекс догоняется при старте сессии Claude Code»;
3. «Позже — включу командой `/memory-search autoindex on`».

```bash
JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-launchd.sh" --data "${CLAUDE_PLUGIN_DATA}"
```

Хук SessionStart включён всегда, выбирать его не нужно. Linux (скрипт выходит с кодом 2) → показать напечатанную строку `@reboot …` и сказать добавить её через `crontab -e` самому; crontab не редактируем.

## Шаг 9 — права (с согласия)

Показать `assets/settings-snippet.json` и объяснить одной фразой: без него Claude Code спрашивает разрешение на каждый поиск. `AskUserQuestion`: «В это хранилище — `<vault>/.claude/settings.local.json` (рекомендую)» / «Во все проекты — `~/.claude/settings.json`» / «Не надо».
Merge: файл есть → `Read`, дописать в `permissions.allow` только недостающие строки, остальное не трогать; нет → `Write` со сниппетом. Показать добавленные строки. Отказ — принять молча. `--auto` → SKIPPED.

## Шаг 10 — подсказка в CLAUDE.md (с согласия)

Заполнить `assets/claude-md-snippet.md`: `{{COLLECTION_LINES}}` → по строке на коллекцию «- `<slug>` — `<папка от корня vault>/`: <описание>»; `{{FRESHNESS}}` → «через минуту после записи» при launchd, «в следующей сессии (или после `/memory-search reindex`)» при режиме «только хук». Ни одного `{{…}}` в итоге.
`AskUserQuestion`: «Дописать в `<vault>/CLAUDE.md`» / «В `~/.claude/CLAUDE.md` (все проекты)» / «Не надо». Секция `## Поиск по смыслу` уже есть → заменить её целиком, не дублировать. `--auto` → SKIPPED.

## Шаг 11 — смоук и финал

1. Дождаться сборки: уведомление о фоновой задаче, либо повторять `show-log.sh setup-build 1` до 10 минут — пока нет строки `reindex setup:`. Не дождались → строка «векторы» = PENDING (poller/хук доделают), остальное проверить.
2. Проверки:

```bash
JMS_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/show-log.sh" setup-build 3
qmd status
qmd search "<2–3 основы слов из заголовка-примера шага 3>" -c <slug> -n 3
qmd query "vec: <пересказ темы той же заметки другими словами>" --no-rerank -c <slug> -n 3
```

   Только typed `vec:` и `--no-rerank`: `qmd vsearch` и `qmd query` без префикса расширяют запрос генератором (1,2 ГБ скачивания), реранк тянет ещё 610 МБ.

   Заметка-пример в топ-3 → PASS. Проверять по одной коллекции, первой выбранной.
3. Инструмент `mcp__plugin_jadlis-memory-search_qmd__status`: ответил — PASS (новые коллекции он всё равно увидит только после перезапуска); недоступен — «после перезапуска».

Таблица:

| Проверка | Итог | Детали |
|---|---|---|
| Node ≥ 22 / qmd | PASS/FAIL | версии |
| Хранилище | PASS | путь |
| Коллекции | PASS/SKIPPED | slug → папка, число заметок |
| Описания | PASS | сколько записано |
| Полнотекстовый индекс | PASS/FAIL | Total из `qmd status` |
| Векторы | PASS/PENDING/FAIL | Vectors, pending |
| `qmd search` / `qmd query vec:` | PASS/FAIL | заметка-пример на месте N |
| Автообновление | launchd / только хук / позже / crontab | `state = …` |
| Права | PASS/SKIPPED | файл |
| CLAUDE.md | PASS/SKIPPED | файл |
| MCP | PASS / после перезапуска | |

Финал ровно так:

```
Готово: <N> коллекций, <M> заметок в индексе.
Перезапусти Claude Code — MCP-сервер qmd читает список коллекций только при старте.
Дальше: /memory-search <вопрос>, например «где я писал про переезд».
Лог сборки: ${CLAUDE_PLUGIN_DATA}/logs/setup-build.log
```

FAIL — под таблицей одна строка на каждый: причина и команда-лекарство. `/memory-search` сам не запускать.
