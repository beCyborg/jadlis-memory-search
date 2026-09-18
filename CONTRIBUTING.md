Русский · [English](#english)

# Как предложить правку

Репозиторий публичный, пишет в него только владелец. Правки — через **форк + pull request**.

1. Форк и ветка от `main`.
2. Перед коммитом: `claude plugin validate . --strict`, `bash -n scripts/*.sh`,
   `node --check scripts/inventory.mjs`, `node --test tests/`, `gitleaks git .`; README — по
   контракту (RU + EN, одинаковые H2, без Mermaid).
3. Одна тема — один PR. В описании — что меняется для получателя.
4. Ключи, почты, личные пути и имена папок из чужих хранилищ в репо не попадают; примеры —
   синтетические.

Скрипты — только bash, без zsh-конструкций: режим «только хук» должен работать и на Linux. Путь
к домашней папке в скрипты и в шаблон launchd не запекается. Смена имени MCP-сервера `qmd`,
метки launchd `com.jadlis.memory-search.watch` или раскладки папки данных плагина = мажорный бамп
версии.

Релизы и теги (`jadlis-memory-search--vX.Y.Z`) делает владелец. Тексты и код написаны вместе
с Claude Code; за содержание отвечает владелец. Поиск делает [qmd](https://github.com/tobi/qmd)
(MIT) — баги самого поиска уходят туда.

---

## English

Public repository, owner-only writes. Contributions via **fork + pull request**: branch from `main`,
run `claude plugin validate . --strict`, `bash -n scripts/*.sh`, `node --check scripts/inventory.mjs`,
`node --test tests/` and `gitleaks git .`, keep README RU/EN in sync (same H2 set, no Mermaid), one
topic per PR, no keys, personal paths or real vault folder names — examples are synthetic.

Scripts are bash only, no zsh-isms, and never hard-code the home directory. Renaming the `qmd` MCP
server, the launchd label `com.jadlis.memory-search.watch` or the plugin data layout is a major bump.

Releases and tags (`jadlis-memory-search--vX.Y.Z`) are cut by the owner. Text and code are written
together with Claude Code; the owner is accountable for the content. Search itself is
[qmd](https://github.com/tobi/qmd) (MIT) — bugs in the engine belong upstream.
