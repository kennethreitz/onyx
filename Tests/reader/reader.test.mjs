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
for (const f of ['marked.js', 'marked-footnote.js', 'typeset.js', 'reader.js']) {
  vm.runInContext(fs.readFileSync(path.join(web, f), 'utf8'), ctx, { filename: f });
  if (f !== 'reader.js') {
    Object.assign(ctx, window);   // UMD builds hang their globals on window/self
    // In a browser globalThis === window; in this vm they are distinct, so the
    // reader would skip marked-footnote unless we attach it to window too.
    if (ctx.marked) window.marked = ctx.marked;
    if (ctx.markedFootnote) window.markedFootnote = ctx.markedFootnote;
  }
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

// --- Footnotes / sidenotes ---------------------------------------------------
// The fixture mirrors the structure of a long essay with five named footnotes
// defined at the end (H1 first, named [^sn-…] refs in body paragraphs, one
// def per line). It is synthetic; it does not use anyone's private text.

const namedFixture = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures/named-sidenotes.md'), 'utf8');

function sectionIndex(out) {
  return out.search(/<section[^>]*class="footnotes"/);
}

test('named footnotes at the end of the source become a notes section after the title, not before it', () => {
  const out = html(namedFixture);
  const fn = sectionIndex(out);
  const h1 = out.indexOf('<h1');
  assert.ok(fn >= 0, 'expected a footnotes section');
  assert.ok(h1 >= 0, 'expected an h1');
  assert.ok(h1 < fn, `footnotes section must come after the title (h1@${h1}, fn@${fn})`);
  assert.equal((out.match(/data-footnote-ref/g) || []).length, 5);
  assert.match(out, /id="footnote-sn-prodromal-signs"/);
  assert.match(out, /id="footnote-sn-malachi-learning"/);
  // definitions should not leak as raw paragraphs
  assert.doesNotMatch(out, /\[\^sn-prodromal-signs\]:/);
});

test('numeric footnotes also stay below the body', () => {
  const out = html('# Num\n\nHello.[^1] There.[^2]\n\n[^1]: first note\n[^2]: second note\n');
  const fn = sectionIndex(out);
  const h1 = out.indexOf('<h1');
  const p = out.indexOf('<p>');
  assert.ok(fn > h1 && fn > p, `section should follow body (h1@${h1}, p@${p}, fn@${fn})`);
  assert.equal((out.match(/data-footnote-ref/g) || []).length, 2);
});

test('multi-paragraph and list-context footnotes still collect at the end', () => {
  const out = html(`# T

A claim in a list:

- first item
- second with a note.[^long]
- third

> A quote with a note.[^q]

[^long]: First paragraph of the note.

    Second paragraph, indented, continues the same note.

[^q]: A short quoted-context note.
`);
  const fn = sectionIndex(out);
  assert.ok(fn > out.indexOf('<h1'), 'section after title');
  assert.ok(fn > out.indexOf('<ul'), 'section after the list');
  assert.ok(fn > out.indexOf('<blockquote'), 'section after the quote');
  assert.equal((out.match(/data-footnote-ref/g) || []).length, 2);
  assert.match(out, /Second paragraph, indented/);
});

test('source-line markers still map the heading and body when footnotes exist', () => {
  const md = '# T\n\nHello.[^1]\n\n[^1]: a note\n';
  const m = marks(md);
  assert.deepEqual(m[0], [0, 1]); // heading at line 0
  assert.ok(m.some(([line]) => line === 2), `expected a marker at line 2, got ${JSON.stringify(m)}`);
  // the collected footnotes section must not steal line 0
  const raw = (md) => ctx.window.Onyx._html(md);
  const out = raw(md);
  assert.doesNotMatch(out, /<!--L0:1--><section/);
  assert.match(out, /<!--L0:1--><h1/);
});

test('canvas cards: fragment renders against the card context, without line markers', () => {
  const out = ctx.window.Onyx.fragment('# Card\nSee [[Hecate]] and ==this==', { links: { hecate: { path: 'AI/Hecate.md', name: 'Hecate' } }, embeds: {} });
  assert.match(out, /<h1>Card<\/h1>/);
  assert.match(out, /data-path="AI\/Hecate\.md"/);
  assert.match(out, /<mark>this<\/mark>/);
  assert.doesNotMatch(out, /<!--L\d/);
  // the reader's own links are untouched afterwards
  assert.doesNotMatch(ctx.window.Onyx._html('[[Hecate]]'), /AI\/Hecate/);
});

// --- Typeset reading (typeset.js) ---------------------------------------------
const T = () => ctx.window.OnyxTypeset;

test('smart quotes curl by context, including across inline markup', () => {
  assert.equal(T().smarten('"Quotes," she said, "should curl \'the right way\'."'), '\u201cQuotes,\u201d she said, \u201cshould curl \u2018the right way\u2019.\u201d');
  assert.equal(T().smarten("don't, it's, Requests' API"), 'don\u2019t, it\u2019s, Requests\u2019 API');
  assert.equal(T().smarten("the '90s and rock 'n' roll"), 'the \u201990s and rock \u2019n\u2019 roll');
  // a closing quote right after </em>: the previous text node ended in a letter
  assert.equal(T().smarten('" next', 'd'), '\u201d next');
  assert.equal(T().smarten('"open', ' '), '\u201copen');
});

test('dashes and ellipses', () => {
  assert.equal(T().smarten('1914--1918'), '1914\u20131918');
  assert.equal(T().smarten('the em dash---which'), 'the em dash\u2014which');
  assert.equal(T().smarten('a note -- and more'), 'a note \u2014 and more');
  assert.equal(T().smarten('Letters - Aleph'), 'Letters \u2013 Aleph');
  assert.equal(T().smarten('well-known'), 'well-known');
  assert.equal(T().smarten('wait...'), 'wait\u2026');
  assert.equal(T().smarten('<!-- x -->'), '<!-- x -->');
});

test('ties keep short words with the next one', () => {
  assert.equal(T().tie('I think a cat saw Dr. Who on p. 5'), 'I\u00a0think a\u00a0cat saw Dr.\u00a0Who on p.\u00a05');
  assert.equal(T().tie('it took 300 ms'), 'it took 300\u00a0ms');
});

test('runs of capitals become small caps; roman numerals and shouting do not', () => {
  const words = (s) => Array.from(T().smallCapsRanges(s), ([a, b]) => s.slice(a, b));   // a local array (the scripts run in a vm realm)
  assert.deepEqual(words('The PSF ships Python; HTTP carries the API.'), ['PSF', 'HTTP', 'API']);
  assert.deepEqual(words('Two APIs, three PRs and AT&T'), ['API', 'PR', 'AT&T']);
  assert.deepEqual(words('MP3 and H2O'), ['MP3', 'H2O']);
  assert.deepEqual(words('World War II, Henry VIII, Part IV'), []);
  assert.deepEqual(words('WHEN SOMEONE SHOUTS THREE WORDS'), []);
  assert.deepEqual(words('iOS and macOS, a I'), []);
});

test('hyphenation language comes from frontmatter lang, else English', () => {
  assert.equal(T().language([{ key: 'lang', value: 'de' }]), 'de');
  assert.equal(T().language([{ key: 'language', value: 'pt-BR' }]), 'pt-BR');
  assert.equal(T().language([{ key: 'lang', value: 'not a tag!' }]), 'en');
  assert.equal(T().language([]), 'en');
});

test('apply sets lang on the reader root (and the document), defaulting to en', () => {
  const html = { lang: 'fr' }, body = { lang: '' };
  const page = { lang: '', querySelector() { return null; }, querySelectorAll() { return []; },
                 ownerDocument: { documentElement: html, body } };
  T().apply(page, { props: [] });           // typeset off: still set lang for hyphenation
  assert.equal(page.lang, 'en');
  assert.equal(html.lang, 'en');
  assert.equal(body.lang, 'en');
  T().apply(page, { props: [{ key: 'lang', value: 'de' }] });
  assert.equal(page.lang, 'de');
  assert.equal(html.lang, 'de');
});

test('numeric table cells are recognised for right alignment', () => {
  for (const v of ['4.2', '1,234', '45%', '$12.50', '(3.1)', '−7', '302.5']) assert.ok(T().NUM.test(v), v);
  for (const v of ['2.0 beta', 'n/a', 'Python 3', 'v1.0']) assert.ok(!T().NUM.test(v), v);
});

test('the specimen fixture parses: notes, table, figure and code survive', () => {
  const fx = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures/typeset-specimen.md'), 'utf8');
  const out = html(fx.replace(/^---[\s\S]*?\n---\n/, ''));
  assert.equal((out.match(/data-footnote-ref/g) || []).length, 6);
  assert.match(out, /<table>/);
  assert.match(out, /<img src="[^"]*chart\.svg"[^>]*title="Downloads per month/);
  assert.match(out, /<code class="language-python">print\(&quot;--- don't touch ---&quot;\)/);
  assert.match(out, /<blockquote>/);
});
