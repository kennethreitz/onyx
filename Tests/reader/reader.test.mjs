// Reader typesetting tests: loads the real Resources/web scripts into a stub DOM and checks
// the HTML Onyx.renders. Run with `node --test Tests/reader` (also part of `make test`).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const web = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../Resources/web');
// Anything the scripts touch at load time: every property is a callable no-op that returns itself.
const stub = () => new Proxy(function () {}, {
  get: (t, k) => k === Symbol.toPrimitive ? () => 0 : k === 'length' ? 0 : stub(),
  apply: () => stub(), construct: () => stub(),
});
const window = { innerHeight: 800, innerWidth: 1000, scrollY: 0, addEventListener() {}, scrollTo() {} };
const ctx = vm.createContext({ window, document: stub(), console, setTimeout, clearTimeout, requestAnimationFrame: f => setTimeout(f, 0),
  getComputedStyle: () => stub(), NodeFilter: { SHOW_COMMENT: 128 }, ResizeObserver: class { observe() {} }, MutationObserver: class { observe() {} } });
ctx.self = ctx.globalThis = ctx; Object.assign(window, { document: ctx.document });
for (const f of ['marked.js', 'marked-footnote.js', 'reader.js']) {
  vm.runInContext(fs.readFileSync(path.join(web, f), 'utf8'), ctx, { filename: f });
  if (f !== 'reader.js') { Object.assign(ctx, window); }   // UMD builds hang their globals on window/self
}
const html = (md) => ctx.window.Onyx._html(md).replace(/<!--L\d+:\d+-->/g, '');
const marks = (md) => [...ctx.window.Onyx._html(md).matchAll(/<!--L(\d+):(\d+)-->/g)].map(m => [+m[1], +m[2]]);

test('single newlines inside a paragraph are line breaks (Obsidian default)', () => {
  const out = html('**Domain**: Communication\n**Symbol**: ☿\n**Roman Equivalent**: Mercury\n');
  assert.match(out, /<p><strong>Domain<\/strong>: Communication<br>\s*<strong>Symbol<\/strong>: ☿<br>\s*<strong>Roman Equivalent<\/strong>: Mercury<\/p>/);
});

test('blank lines still separate paragraphs', () => {
  const out = html('one\n\ntwo\n');
  assert.equal((out.match(/<p>/g) || []).length, 2);
  assert.doesNotMatch(out, /<br>/);
});

test('lists, tables and code blocks are not broken', () => {
  const list = html('- a\n- b\n- c\n');
  assert.equal((list.match(/<li>/g) || []).length, 3);
  assert.doesNotMatch(list, /<br>/);
  const table = html('| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |\n');
  assert.match(table, /<table>/);
  assert.equal((table.match(/<tr>/g) || []).length, 3);
  assert.doesNotMatch(table, /<br>/);
  const code = html('```\nline one\nline two\n```\n');
  assert.match(code, /line one\nline two/);
  assert.doesNotMatch(code, /<br>/);
  const indented = html('    x = 1\n    y = 2\n');
  assert.doesNotMatch(indented, /<br>/);
});

test('blockquotes break lines like paragraphs; callouts keep their title', () => {
  const q = html('> first\n> second\n');
  assert.match(q, /<blockquote>\s*<p>first<br>\s*second<\/p>/);
  const c = html('> [!note] Heads up\n> line one\n> line two\n');
  assert.match(c, /class="callout" data-callout="note"/);
  assert.match(c, /callout-title">Heads up\./);
  assert.match(c, /callout-content"><p>line one<br>\s*line two<\/p>/);
  assert.doesNotMatch(c, /Heads up<br>/);
});

test('wikilinks with aliases survive the break', () => {
  const out = html('**Roman Equivalent**: [[Mercury|Mercury]]\n**Next**: x\n');
  assert.match(out, /internal-link[^>]*>Mercury<\/a><br>/);
});

test('source-line markers are unchanged by line breaks (scroll mapping)', () => {
  const md = '# T\n\n**A**: 1\n**B**: 2\n**C**: 3\n\npara\n\n- x\n- y\n';
  assert.deepEqual(marks(md), [[0, 1], [2, 3], [6, 1], [8, 2]]);
});
