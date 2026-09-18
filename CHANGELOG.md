# Changelog — jadlis-memory-search

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/), версии — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [1.0.0] — 2026-09-18 — первый выпуск: поиск по смыслу в заметках Obsidian / first release: semantic search over Obsidian notes

### Для человека

- Одна установка и `/jadlis-memory-search:memory-search-setup` ставят локальный поиск по смыслу над
  выбранными папками хранилища Obsidian: настройка находит хранилище, показывает папки со счётом
  заметок, Claude пишет каждой описание в одну строку, индекс строится на твоём Mac — без ключей и
  облака.
- Индекс обновляется сам: фоновый опрос через launchd раз в минуту и полная сверка раз в час,
  запасной путь — при старте сессии Claude Code (на Linux — только он).
- Спрашиваешь обычными словами или через `/jadlis-memory-search:memory-search`; обслуживание —
  `status`, `reindex`, `add`, `remove`, `autoindex on|off|status`. Поиск делает qmd (Tobi Lütke,
  npm `@tobilu/qmd`), плагин — обвязка вокруг него.

### For agents

- Added: `.claude-plugin/plugin.json` — `jadlis-memory-search` 1.0.0, no `userConfig`; `.mcp.json` —
  server `qmd` (stdio, `bash ${CLAUDE_PLUGIN_ROOT}/scripts/qmd-mcp.sh` → `qmd mcp`, env
  `QMD_EMBED_CONTEXT_SIZE=506`, `QMD_EMBED_PARALLELISM=1`); tools
  `mcp__plugin_jadlis-memory-search_qmd__{query,get,multi_get,status}`.
- Added: `hooks/hooks.json` — `SessionStart` `startup|resume`, async, timeout 30 →
  `scripts/session-start.sh` (syncs scripts into `${CLAUDE_PLUGIN_DATA}/bin`, `launchctl kickstart -k`
  on change, background reindex under a mkdir lock when notes are newer than `state/last-index`).
- Added: `scripts/{qmd-env,qmd-mcp,qmd-reindex,qmd-watch,session-start,install-launchd,preflight,show-log}.sh`,
  `scripts/launchd.plist.template` (label `com.jadlis.memory-search.watch`, no `HOME` key),
  `scripts/inventory.mjs` (folder inventory, skip heuristics, `--folder` summary, `--slug` RU→Latin
  transliteration) + `tests/inventory.test.mjs`. All scripts bash, no zsh-isms.
- Added: `skills/memory-search-setup/` (SKILL.md, `references/inventory-rules.md`,
  `assets/{claude-md-snippet.md,settings-snippet.json}`) and `skills/memory-search/` (SKILL.md,
  `references/gotchas.md`): typed `lex` + `vec` queries, `intent` required, `rerank:false`.
- Added: `README.md` + `README.en.md` (same H2 set, no Mermaid), `CONTRIBUTING.md`,
  `docs/img/prompts/jadlis-memory-search.md`, `.github/workflows/ci.yml` →
  `beCyborg/jadlis-hub/.github/workflows/plugin-ci.yml@main`.
- Migration: none — first release. The qmd config (`~/.config/qmd/index.yml`) and index
  (`~/.cache/qmd/`) belong to qmd and survive `claude plugin uninstall`.
