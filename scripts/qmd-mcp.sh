#!/usr/bin/env bash
# stdio MCP server entry point. Nothing may reach stdout before `exec qmd mcp`.
set -u
. "$(cd "$(dirname "$0")" && pwd)/qmd-env.sh" >/dev/null 2>&1 || {
  echo "jadlis-memory-search: не удалось загрузить qmd-env.sh рядом с qmd-mcp.sh" >&2
  exit 1
}

if ! command -v node >/dev/null 2>&1; then
  echo "jadlis-memory-search: не найден Node.js — нужна версия 22 или новее. Установите: brew install node" >&2
  exit 1
fi
if ! jms_node_ok; then
  echo "jadlis-memory-search: Node.js $(node -v 2>/dev/null) слишком старый — нужна версия 22 или новее. Обновите: brew install node (или brew upgrade node)" >&2
  exit 1
fi
if ! jms_qmd_ok; then
  echo "jadlis-memory-search: не найден qmd. Установите: npm install -g @tobilu/qmd" >&2
  exit 1
fi

# Run from / so a project-local .qmd/ in the session's cwd cannot shadow the global index.
cd / || exit 1
exec qmd mcp
