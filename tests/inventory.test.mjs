import { test } from 'node:test';
import assert from 'node:assert/strict';
import { slugify, classify, titleOf, tagsOf, SKIP } from '../scripts/inventory.mjs';

test('slugify: required examples', () => {
  assert.equal(slugify('Входящие'), 'vkhodyashchie');
  assert.equal(slugify('В ручную'), 'v-ruchnuyu');
  assert.equal(slugify('Знания'), 'znaniya');
});

test('slugify: letters, Ukrainian, Latin diacritics, decomposed input', () => {
  assert.equal(slugify('Щука Ёж'), 'shchuka-yozh');
  assert.equal(slugify('Їжак Єнот ґанок і'), 'yizhak-yenot-ganok-i');
  assert.equal(slugify('Café Notes'), 'cafe-notes');
  assert.equal(slugify('Мой'.normalize('NFD')), 'moy');
  assert.equal(slugify('  --Ресерчи & TL;DR 2026-- '), 'reserchi-tl-dr-2026');
  assert.equal(slugify('Объявления'), 'obyavleniya');
  assert.match(slugify('SWOT-Новости'), /^[a-zA-Z0-9_-]+$/);
});

test('slugify: collisions get -2, -3', () => {
  assert.equal(slugify('Знания', ['znaniya']), 'znaniya-2');
  assert.equal(slugify('Знания', ['znaniya', 'znaniya-2']), 'znaniya-3');
  assert.equal(slugify('Знания', ['other']), 'znaniya');
});

test('slugify: empty or unmappable → notes', () => {
  assert.equal(slugify(''), 'notes');
  assert.equal(slugify('🙂 !!!'), 'notes');
  assert.equal(slugify('日本'), 'notes');
  assert.equal(slugify('', ['notes']), 'notes-2');
});

test('classify: service folders', () => {
  assert.equal(classify({ name: '.obsidian', md: 0, other: 40 }).skip, SKIP.service);
  assert.equal(classify({ name: '.trash', md: 50, other: 0 }).skip, SKIP.service);
});

test('classify: attachments by name and by ratio', () => {
  assert.equal(classify({ name: 'Файлы', md: 1, other: 12 }).skip, SKIP.attachments);
  assert.equal(classify({ name: 'assets', md: 0, other: 3 }).skip, SKIP.attachments);
  assert.equal(classify({ name: 'Разное', md: 2, other: 30 }).skip, SKIP.attachments);
  // notes-heavy folder whose name happens to match stays a candidate
  assert.equal(classify({ name: 'Social media', md: 200, other: 5 }).skip, null);
  // few other files: ratio rule needs other >= 10
  assert.notEqual(classify({ name: 'Проекты', md: 1, other: 9 }).skip, SKIP.attachments);
});

test('classify: templates by name and by content', () => {
  assert.equal(classify({ name: 'Шаблоны', md: 3, other: 0 }).skip, SKIP.templates);
  assert.equal(classify({ name: 'Templates', md: 20, other: 0 }).skip, SKIP.templates);
  assert.equal(classify({ name: 'Разное', md: 10, other: 0, templateHits: 5, templateSampled: 10 }).skip, SKIP.templates);
  assert.equal(classify({ name: 'Разное', md: 10, other: 0, templateHits: 4, templateSampled: 10 }).skip, null);
});

test('classify: empty below 3 notes', () => {
  assert.equal(classify({ name: 'Пусто', md: 1, other: 0 }).skip, SKIP.empty);
  assert.equal(classify({ name: 'Ноль', md: 0, other: 0 }).skip, SKIP.empty);
  assert.equal(classify({ name: 'Три', md: 3, other: 0 }).skip, null);
});

test('classify: huge is a flag, not a skip', () => {
  const r = classify({ name: 'Архив', md: 5001, other: 10 });
  assert.equal(r.skip, null);
  assert.equal(r.huge, true);
  assert.equal(classify({ name: 'Архив', md: 5000, other: 0 }).huge, false);
});

test('titleOf: frontmatter title, heading, filename', () => {
  assert.equal(titleOf('---\ntitle: "Закаты"\n---\n# Другое', '/v/a.md'), 'Закаты');
  assert.equal(titleOf('---\ntags: [a]\n---\n\n# Заголовок  \ntext', '/v/a.md'), 'Заголовок');
  assert.equal(titleOf('просто текст', '/v/Имя файла.md'), 'Имя файла');
});

test('tagsOf: list, inline and body tags', () => {
  assert.deepEqual(tagsOf('---\ntags:\n  - план\n  - "Qmd"\n---\ntext #идея and #123 `#code`').sort(), ['идея', 'план', 'qmd'].sort());
  assert.deepEqual(tagsOf('---\ntags: [a, b]\n---\n').sort(), ['a', 'b']);
  assert.deepEqual(tagsOf('---\ntags: one\n---\n# Heading'), ['one']);
});
