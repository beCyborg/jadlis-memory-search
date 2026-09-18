#!/usr/bin/env node
// Vault inventory for memory-search-setup. Node >= 22, no dependencies.
//   inventory.mjs <vault> [--depth 1] [--json|--table]
//   inventory.mjs <vault> --folder <rel> [--titles 40] [--samples 5] [--tags 10] [--json]
//   inventory.mjs --slug "<name>" [--taken a,b]
import { readdirSync, statSync, realpathSync, openSync, readSync, closeSync } from 'node:fs';
import { join, basename, extname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const SKIP = {
  service: 'служебная',
  attachments: 'вложения',
  templates: 'шаблоны',
  empty: 'пусто',
};
export const HUGE_MD = 5000;
const WALK_SKIP = new Set(['.git', 'node_modules', '.obsidian', '.trash']);
const ATTACH_RE = /attach|вложен|файлы|assets|media|images|resources/i;
const TEMPLATE_RE = /templat|шаблон/i;

// ---------- slug ----------
const TRANSLIT = {
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'yo', ж: 'zh', з: 'z', и: 'i',
  й: 'y', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't',
  у: 'u', ф: 'f', х: 'kh', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'shch', ъ: '', ы: 'y', ь: '',
  э: 'e', ю: 'yu', я: 'ya', і: 'i', ї: 'yi', є: 'ye', ґ: 'g',
};

export function slugify(name, taken = []) {
  const lower = String(name ?? '').normalize('NFC').toLowerCase();
  let out = '';
  for (const ch of lower) out += ch in TRANSLIT ? TRANSLIT[ch] : ch;
  out = out.normalize('NFD').replace(/\p{M}/gu, '');
  out = out.replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  if (!/^[a-zA-Z0-9_-]+$/.test(out)) out = 'notes';
  const used = new Set([...taken].map((t) => String(t).trim()).filter(Boolean));
  if (!used.has(out)) return out;
  for (let i = 2; ; i++) if (!used.has(`${out}-${i}`)) return `${out}-${i}`;
}

// ---------- classification ----------
// stats: { name, md, other, templateHits, templateSampled }
export function classify(stats) {
  const { name = '', md = 0, other = 0, templateHits = 0, templateSampled = 0 } = stats;
  const huge = md > HUGE_MD;
  const total = md + other;
  const mdShare = total > 0 ? md / total : 0;
  let skip = null;
  if (name.startsWith('.') || name === 'node_modules') skip = SKIP.service;
  // Name-based attachment match only counts when notes are a minority, so a
  // notes folder like "Social media" is not dropped.
  else if (ATTACH_RE.test(name) && mdShare < 0.5) skip = SKIP.attachments;
  else if (other >= 10 && mdShare < 0.2) skip = SKIP.attachments;
  else if (TEMPLATE_RE.test(name)) skip = SKIP.templates;
  else if (templateSampled > 0 && templateHits / templateSampled >= 0.5) skip = SKIP.templates;
  else if (md < 3) skip = SKIP.empty;
  return { skip, huge };
}

// ---------- file helpers ----------
function readHead(file, bytes = 16384) {
  let fd;
  try {
    fd = openSync(file, 'r');
    const buf = Buffer.alloc(bytes);
    const n = readSync(fd, buf, 0, bytes, 0);
    return buf.subarray(0, n).toString('utf8');
  } catch {
    return '';
  } finally {
    if (fd !== undefined) try { closeSync(fd); } catch {}
  }
}

export function splitFrontmatter(text) {
  const t = text.replace(/^\uFEFF/, '');
  const m = t.match(/^---\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/);
  if (!m) return { fm: '', body: t };
  return { fm: m[1], body: t.slice(m[0].length) };
}

function unquote(v) {
  const s = v.trim();
  if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) return s.slice(1, -1);
  return s;
}

export function titleOf(text, file) {
  const { fm, body } = splitFrontmatter(text);
  const tm = fm.match(/^title:[ \t]*(.+)$/m);
  if (tm && unquote(tm[1])) return unquote(tm[1]);
  const hm = body.match(/^#[ \t]+(.+?)[ \t#]*$/m);
  if (hm) return hm[1].trim();
  return basename(file, extname(file));
}

export function tagsOf(text) {
  const { fm, body } = splitFrontmatter(text);
  const tags = [];
  const lines = fm.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^(tags|tag):[ \t]*(.*)$/);
    if (!m) continue;
    const rest = m[2].trim();
    if (rest) {
      rest.replace(/^\[|\]$/g, '').split(/[,\s]+/).forEach((t) => t && tags.push(t));
    } else {
      for (let j = i + 1; j < lines.length; j++) {
        const li = lines[j].match(/^[ \t]*-[ \t]+(.+)$/);
        if (!li) break;
        tags.push(li[1]);
      }
    }
  }
  const noCode = body.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, '');
  for (const m of noCode.matchAll(/(?:^|[\s(])#([\p{L}\p{N}_\/-]+)/gu)) {
    if (/[^\d]/u.test(m[1])) tags.push(m[1]);
  }
  return tags
    .map((t) => unquote(t).replace(/^#/, '').trim().toLowerCase())
    .filter((t) => t && /[^\d]/u.test(t));
}

function excerptOf(text, n = 300) {
  const { body } = splitFrontmatter(text);
  const flat = body.replace(/\s+/g, ' ').trim();
  return flat.length > n ? `${flat.slice(0, n)}…` : flat;
}

// Walk a directory: md files (with mtime), other file count, bytes.
function walk(dir, acc = { md: [], other: 0, bytes: 0, otherLatest: 0 }) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return acc; }
  for (const e of entries) {
    if (e.name.startsWith('.') || WALK_SKIP.has(e.name)) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) { walk(p, acc); continue; }
    if (e.isSymbolicLink()) {
      let st; try { st = statSync(p); } catch { continue; }
      if (!st.isFile()) continue;
      addFile(acc, p, st);
      continue;
    }
    if (!e.isFile()) continue;
    let st; try { st = statSync(p); } catch { continue; }
    addFile(acc, p, st);
  }
  return acc;
}
function addFile(acc, p, st) {
  acc.bytes += st.size;
  if (extname(p).toLowerCase() === '.md') acc.md.push({ path: p, mtime: st.mtimeMs });
  else { acc.other++; if (st.mtimeMs > acc.otherLatest) acc.otherLatest = st.mtimeMs; }
}

function evenlySpread(arr, n) {
  if (arr.length <= n) return arr.slice();
  if (n <= 1) return [arr[0]];
  const out = [];
  for (let i = 0; i < n; i++) out.push(arr[Math.round((i * (arr.length - 1)) / (n - 1))]);
  return out;
}

const day = (ms) => (ms > 0 ? new Date(ms).toISOString().slice(0, 10) : null);
const mb = (b) => Math.round((b / 1048576) * 100) / 100;

function folderRow(label, acc) {
  const byNew = acc.md.slice().sort((a, b) => b.mtime - a.mtime);
  const samples = byNew.slice(0, 3).map((f) => titleOf(readHead(f.path), f.path));
  const probe = evenlySpread(acc.md.slice().sort((a, b) => (a.path < b.path ? -1 : 1)), 10);
  const templateHits = probe.filter((f) => readHead(f.path).includes('{{')).length;
  const latest = Math.max(byNew[0]?.mtime ?? 0, acc.md.length ? 0 : acc.otherLatest);
  const { skip, huge } = classify({
    name: label, md: acc.md.length, other: acc.other, templateHits, templateSampled: probe.length,
  });
  return {
    folder: label, md: acc.md.length, other: acc.other, mb: mb(acc.bytes),
    lastModified: day(latest), samples, skip, huge,
  };
}

export function inventory(vault, depth = 1) {
  const rows = [];
  const visit = (abs, rel, level) => {
    let entries;
    try { entries = readdirSync(abs, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (!e.isDirectory()) continue;
      const relName = rel ? `${rel}/${e.name}` : e.name;
      const p = join(abs, e.name);
      const service = e.name.startsWith('.') || WALK_SKIP.has(e.name);
      // Service dirs get a row but are not walked (.git and friends can be huge).
      const acc = service ? { md: [], other: 0, bytes: 0, otherLatest: 0 } : walk(p);
      const row = folderRow(relName, acc);
      if (service) row.skip = SKIP.service;
      rows.push(row);
      if (!service && level < depth) visit(p, relName, level + 1);
    }
  };
  visit(vault, '', 1);

  // Notes directly in the vault root.
  const rootAcc = { md: [], other: 0, bytes: 0, otherLatest: 0 };
  for (const e of readdirSync(vault, { withFileTypes: true })) {
    if (e.name.startsWith('.') || !(e.isFile() || e.isSymbolicLink())) continue;
    const p = join(vault, e.name);
    let st; try { st = statSync(p); } catch { continue; }
    if (st.isFile()) addFile(rootAcc, p, st);
  }
  if (rootAcc.md.length || rootAcc.other) rows.push(folderRow('(корень)', rootAcc));

  // Candidates first, then skipped; each group by note count desc.
  rows.sort((a, b) => Number(a.skip !== null) - Number(b.skip !== null)
    || b.md - a.md || a.folder.localeCompare(b.folder, 'ru'));
  return rows;
}

export function folderDetail(vault, rel, { titles = 40, samples = 5, tags = 10 } = {}) {
  const abs = resolve(vault, rel);
  const acc = walk(abs);
  const byNew = acc.md.slice().sort((a, b) => b.mtime - a.mtime);
  const subfolders = [];
  for (const e of readdirSync(abs, { withFileTypes: true })) {
    if (!e.isDirectory() || e.name.startsWith('.') || WALK_SKIP.has(e.name)) continue;
    subfolders.push({ name: e.name, md: walk(join(abs, e.name)).md.length });
  }
  subfolders.sort((a, b) => b.md - a.md || a.name.localeCompare(b.name, 'ru'));

  const TAG_SCAN = 2000;
  const counts = new Map();
  for (const f of byNew.slice(0, TAG_SCAN)) {
    for (const t of tagsOf(readHead(f.path, 65536))) counts.set(t, (counts.get(t) ?? 0) + 1);
  }
  const topTags = [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, tags)
    .map(([tag, count]) => ({ tag, count }));

  return {
    folder: rel,
    md: acc.md.length,
    other: acc.other,
    titles: byNew.slice(0, titles).map((f) => titleOf(readHead(f.path), f.path)),
    subfolders,
    samples: evenlySpread(byNew, samples).map((f) => {
      const text = readHead(f.path);
      return { title: titleOf(text, f.path), path: f.path.slice(abs.length + 1), excerpt: excerptOf(text) };
    }),
    tags: topTags,
    tagsScanned: Math.min(byNew.length, TAG_SCAN),
  };
}

// ---------- output ----------
const cell = (s) => String(s ?? '').replace(/\|/g, '\\|').replace(/\s+/g, ' ');

function renderTable(rows) {
  const cand = rows.filter((r) => !r.skip);
  const skipped = rows.filter((r) => r.skip);
  const out = [];
  out.push('| # | Папка | Заметок | Других файлов | МБ | Последняя правка | Примеры заголовков |');
  out.push('|---|---|---|---|---|---|---|');
  cand.forEach((r, i) => {
    const name = r.huge ? `${r.folder} (огромная: > ${HUGE_MD} заметок)` : r.folder;
    out.push(`| ${i + 1} | ${cell(name)} | ${r.md} | ${r.other} | ${r.mb} | ${r.lastModified ?? '—'} | ${cell(r.samples.join('; '))} |`);
  });
  if (!cand.length) out.push('| — | нет подходящих папок | | | | | |');
  if (skipped.length) {
    out.push('', 'Пропущено автоматически:', '');
    out.push('| Папка | Причина | Заметок | Других файлов |');
    out.push('|---|---|---|---|');
    for (const r of skipped) out.push(`| ${cell(r.folder)} | ${r.skip} | ${r.md} | ${r.other} |`);
  }
  return out.join('\n');
}

function renderFolder(d) {
  const out = [`## ${d.folder} — ${d.md} заметок`, '', `### Заголовки (новые сверху, ${d.titles.length})`];
  d.titles.forEach((t) => out.push(`- ${t}`));
  out.push('', '### Подпапки');
  if (!d.subfolders.length) out.push('- нет');
  d.subfolders.forEach((s) => out.push(`- ${s.name}: ${s.md}`));
  out.push('', '### Образцы');
  d.samples.forEach((s) => out.push(`- **${s.title}** (${s.path}): ${s.excerpt}`));
  out.push('', `### Теги (просмотрено заметок: ${d.tagsScanned})`);
  if (!d.tags.length) out.push('- нет');
  d.tags.forEach((t) => out.push(`- #${t.tag}: ${t.count}`));
  return out.join('\n');
}

function parseArgs(argv) {
  const a = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (!k.startsWith('--')) { a._.push(k); continue; }
    const [key, inline] = k.slice(2).split(/=(.*)/s);
    if (['json', 'table'].includes(key)) { a[key] = true; continue; }
    a[key] = inline !== undefined ? inline : argv[++i];
  }
  return a;
}

function die(msg) {
  process.stderr.write(`inventory: ${msg}\n`);
  process.exit(1);
}

function main(argv) {
  const a = parseArgs(argv);
  if (a.slug !== undefined) {
    const taken = a.taken ? String(a.taken).split(',') : [];
    process.stdout.write(`${slugify(a.slug, taken)}\n`);
    return;
  }
  const vault = a._[0];
  if (!vault) die('укажите путь к хранилищу: inventory.mjs <vault> [--depth 1] [--json|--table]');
  let st; try { st = statSync(vault); } catch { st = null; }
  if (!st?.isDirectory()) die(`папка не найдена: ${vault}`);
  const num = (v, d) => (v === undefined ? d : Math.max(0, parseInt(v, 10) || 0));

  if (a.folder !== undefined) {
    const abs = resolve(vault, a.folder);
    let fst; try { fst = statSync(abs); } catch { fst = null; }
    if (!fst?.isDirectory()) die(`папка не найдена: ${abs}`);
    const d = folderDetail(vault, a.folder, {
      titles: num(a.titles, 40), samples: num(a.samples, 5), tags: num(a.tags, 10),
    });
    process.stdout.write(`${a.json ? JSON.stringify(d, null, 2) : renderFolder(d)}\n`);
    return;
  }
  const rows = inventory(vault, Math.max(1, num(a.depth, 1)));
  process.stdout.write(`${a.json ? JSON.stringify(rows, null, 2) : renderTable(rows)}\n`);
}

const invokedDirectly = (() => {
  try { return process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); }
  catch { return false; }
})();
if (invokedDirectly) main(process.argv.slice(2));
