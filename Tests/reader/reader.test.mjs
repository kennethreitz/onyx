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
for (const f of ['marked.js', 'marked-footnote.js', 'katex/katex.min.js', 'math.js', 'typeset.js', 'reader.js']) {
  vm.runInContext(fs.readFileSync(path.join(web, f), 'utf8'), ctx, { filename: f });
  if (f !== 'reader.js') {
    Object.assign(ctx, window);   // UMD builds hang their globals on window/self
    // In a browser globalThis === window; in this vm they are distinct, so the
    // reader would skip marked-footnote unless we attach it to window too.
    if (ctx.marked) window.marked = ctx.marked;
    if (ctx.markedFootnote) window.markedFootnote = ctx.markedFootnote;
    if (ctx.katex) window.katex = ctx.katex;
    if (ctx.OnyxMath) window.OnyxMath = ctx.OnyxMath;
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

function cell(html, i = 0) {
  return [...html.matchAll(/<td>([\s\S]*?)<\/td>/g)].map(m => m[1])[i];
}
function links(html) {
  return [...html.matchAll(/data-target="([^"]*)"[^>]*>([^<]*)<\/a>/g)].map(m => [m[1], m[2]]);
}

test('unescaped pipes inside wikilinks do not split table cells', () => {
  const md = `| Stone | Chakra | Planet / Zodiac |
| --- | --- | --- |
| [[Aquamarine]] | Throat ([[Vishuddha]]) | [[Jupiter]], [[Neptune (astrology)|Neptune]] / [[Pisces]], [[Aquarius]] |
`;
  const out = html(md);
  assert.equal((out.match(/<tr>/g) || []).length, 2); // header + one body row
  assert.equal((out.match(/<td>/g) || []).length, 3);
  const planet = cell(out, 2);
  assert.deepEqual(links(planet), [
    ['Jupiter', 'Jupiter'],
    ['Neptune (astrology)', 'Neptune'],
    ['Pisces', 'Pisces'],
    ['Aquarius', 'Aquarius'],
  ]);
  const chakra = cell(out, 1);
  assert.match(chakra, /^Throat \(/);
  assert.deepEqual(links(chakra), [['Vishuddha', 'Vishuddha']]);
  assert.match(chakra, /\)<\/td>$|\)$/);
});

test('escaped pipes inside table wikilinks are alias separators', () => {
  const md = `| x |
| --- |
| [[Jupiter]], [[Neptune (astrology)\\|Neptune]] / [[Pisces]], [[Aquarius]] |
`;
  const out = html(md);
  assert.equal((out.match(/<td>/g) || []).length, 1);
  assert.deepEqual(links(cell(out, 0)), [
    ['Jupiter', 'Jupiter'],
    ['Neptune (astrology)', 'Neptune'],
    ['Pisces', 'Pisces'],
    ['Aquarius', 'Aquarius'],
  ]);
});

test('wikilinks in parentheses inside a table cell render as links', () => {
  const out = html('| Chakra |\n| --- |\n| Third Eye ([[Ajna]]) |\n');
  const c = cell(out, 0);
  assert.match(c, /^Third Eye \(/);
  assert.deepEqual(links(c), [['Ajna', 'Ajna']]);
});

test('escapeWikilinkPipesInTables leaves fenced code and prose alone', () => {
  const esc = ctx.window.Onyx._escapeWikilinkPipesInTables;
  const prose = 'See [[Neptune (astrology)|Neptune]] in prose.';
  assert.equal(esc(prose), prose);
  const fence = '```\n| [[Neptune (astrology)|Neptune]] |\n```\n';
  assert.equal(esc(fence), fence);
  const table = '| [[Neptune (astrology)|Neptune]] |\n';
  assert.equal(esc(table), '| [[Neptune (astrology)\\|Neptune]] |\n');
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

test('==highlight== becomes a mark, including across a line break', () => {
  assert.match(html('a ==one== b'), /<p>a <mark>one<\/mark> b<\/p>/);
  const multi = html('start ==this highlight\ncontinues across a line== end');
  assert.match(multi, /<mark>this highlight<br>\s*continues across a line<\/mark>/);
});

test('mark CSS clones decoration on each line so a wrap does not paint a full-width band', () => {
  const css = fs.readFileSync(path.join(web, 'reader.css'), 'utf8');
  const rule = css.match(/mark,\s*\.highlight\s*\{[^}]*\}/);
  assert.ok(rule, 'mark, .highlight rule');
  assert.match(rule[0], /-webkit-box-decoration-break:\s*clone/);
  assert.match(rule[0], /box-decoration-break:\s*clone/);
  // border-radius makes WKWebView paint the unbroken box as well as the fragments
  assert.doesNotMatch(rule[0], /border-radius/);
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

test('compact table cells (dates, numbers, short tokens) are marked nowrap', () => {
  for (const v of ['2026-11-09', '11/9/26', '4.2', '1,234', 'OK', 'v1.0']) assert.ok(T().isCompact(v), v);
  for (const v of ['2026-11-09 notes', 'A long title', 'Python 3 docs']) assert.ok(!T().isCompact(v), v);
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

// --- Math ($ / $$) -----------------------------------------------------------
test('inline $...$ becomes typeset math, and underscores stay out of <em>', () => {
  const out = html('see $a_1+b^2$ here');
  assert.match(out, /class="math inline"/);
  assert.match(out, /katex/);
  assert.doesNotMatch(out, /<em>/);
});

test('multi-line $$ is display math', () => {
  const out = html('$$\nE = mc^2\n$$\n');
  assert.match(out, /class="math display"/);
  assert.match(out, /katex/);
});

test('currency and spaced dollars are not math', () => {
  const money = html('it costs $5 and $10 today');
  assert.doesNotMatch(money, /class="math/);
  const spaced = html('this is $ not $ math');
  assert.doesNotMatch(spaced, /class="math/);
});

test('math inside a code block is left as text', () => {
  const out = html('```\n$x$\n```\n');
  assert.doesNotMatch(out, /class="math/);
  assert.match(out, /\$x\$/);
});

test('bad TeX shows an inline error instead of breaking the page', () => {
  const out = html('see $\\notacommand$ here');
  assert.match(out, /class="math math-error/);
  assert.doesNotMatch(out, /<pre>/);
  const page = html('# Title\n\n$\\notacommand$\n\nand more\n');
  assert.match(page, /<h1>Title<\/h1>/);
  assert.match(page, /math-error/);
  assert.match(page, /and more/);
});

test('image sizing follows Obsidian: |W, |WxH, alt|W, and Markdown alt sizes', () => {
  const img = (n) => ({ type: 'image', path: `att/${n}`, url: `onyx://vault/att/${n}` });
  const ctxE = { links: {}, embeds: { 'a.png': img('a.png'), 'v.mp4': { type: 'video', path: 'v.mp4', url: 'onyx://vault/v.mp4' } }, mdembeds: {}, base: 'onyx://vault/' };
  const f = (md) => ctx.window.Onyx.fragment(md, ctxE);
  assert.match(f('![[a.png|300]]'), /<img src="onyx:\/\/vault\/att\/a\.png" width="300" alt="a\.png" data-path="att\/a\.png" data-embed="wiki" data-embed-target="a\.png">/);
  assert.match(f('![[a.png|300x200]]'), / width="300" height="200" /);
  const cap = f('![[a.png|A cap|120]]');
  assert.match(cap, / width="120" alt="A cap"/);
  assert.doesNotMatch(cap, /height=/);
  assert.match(f('![[a.png|Just a caption]]'), /<img [^>]*alt="Just a caption"/);
  assert.doesNotMatch(f('![[a.png|Just a caption]]'), /width=/);
  assert.doesNotMatch(f('![[a.png|300px]]'), /width=/);
  assert.match(f('![[v.mp4|320]]'), /<video controls preload="metadata" width="320" src=/);
  assert.match(f('![250](https://example.com/e.jpg)'), /<img src="https:\/\/example\.com\/e\.jpg" width="250" alt="" data-embed="md" data-embed-target="https:\/\/example\.com\/e\.jpg">/);
  assert.match(f('![Doug|100x145](https://example.com/e.jpg)'), / width="100" height="145" alt="Doug"/);
  assert.match(f('![Plain alt](https://example.com/e.jpg)'), /alt="Plain alt" data-embed="md"/);
});

test('sized images keep their block line anchors (drag-to-resize writes back by source line)', () => {
  const out = ctx.window.Onyx._html('intro\n\n![[a.png|300]] and ![[a.png]]\n');
  assert.match(out, /<!--L2:1--><p>/);
});

test('image CSS never upscales past the column, and the resize grip is styled', () => {
  const css = fs.readFileSync(path.join(web, 'reader.css'), 'utf8');
  assert.match(css, /img \{[^}]*max-width: 100%/);
  assert.match(css, /#img-grip \{[^}]*cursor: nwse-resize/);
});


// --- Wide Mermaid / table scroll cues + lightbox --------------------------------

const Tset = () => ctx.window.OnyxTypeset;

test('mermaidFit scales to the bled width until labels would drop below 13px', () => {
  const T = Tset();
  assert.equal(T.MERMAID_FONT_PX, 15);
  assert.equal(T.MERMAID_MIN_LABEL_PX, 13);
  // Fits in the wrap: leave natural, no scroll.
  const natural = T.mermaidFit(400, 500, 15);
  assert.equal(natural.mode, 'natural');
  assert.equal(natural.scrollable, false);
  assert.equal(natural.scale, 1);
  // ~10% over the bleed: 15px * (1000/1100) ≈ 13.6px, still above 13 — fit.
  const modest = T.mermaidFit(1100, 1000, 15);
  assert.equal(modest.mode, 'fit');
  assert.equal(modest.scrollable, false);
  assert.equal(modest.layoutWidth, 1000);
  assert.ok(Math.abs(modest.scale - 1000 / 1100) < 1e-9);
  assert.ok(15 * modest.scale >= 13);
  // 20% over would be 12.5px, under the floor, so this scrolls.
  const justOver = T.mermaidFit(1200, 1000, 15);
  assert.equal(justOver.mode, 'scroll');
  assert.equal(justOver.scrollable, true);
  // 15 * 13/15 = 13 exactly at scale 13/15, i.e. natural / bleed ≤ 15/13 ≈ 1.1538.
  const atFloor = T.mermaidFit(1153.8, 1000, 15);
  assert.equal(atFloor.mode, 'fit');
  assert.ok(15 * atFloor.scale + 1e-6 >= 13);
  // Wider than that: shrink only to the 13px floor and scroll the rest.
  const wide = T.mermaidFit(2000, 1000, 15);
  assert.equal(wide.mode, 'scroll');
  assert.equal(wide.scrollable, true);
  assert.ok(Math.abs(wide.scale - 13 / 15) < 1e-9);
  assert.ok(Math.abs(wide.layoutWidth - 2000 * 13 / 15) < 1e-6);
  assert.ok(wide.layoutWidth > 1000);
  assert.ok(Math.abs(15 * wide.scale - 13) < 1e-9);
});

test('mermaidFit honors a measured label font when it differs from 15px', () => {
  // 18px labels can shrink to 13px (s >= 13/18) and still fit a modestly wider figure.
  const fit = Tset().mermaidFit(1300, 1000, 18);
  assert.equal(fit.mode, 'fit');
  assert.ok(18 * fit.scale >= 13);
  const scroll = Tset().mermaidFit(2000, 1000, 18);
  assert.equal(scroll.mode, 'scroll');
  assert.ok(Math.abs(scroll.scale - 13 / 18) < 1e-9);
});

test('reader CSS fades both overflow edges, hides the native bar, and styles the lightbox', () => {
  const css = fs.readFileSync(path.join(web, 'reader.css'), 'utf8');
  // The global rule hid native bars with display: none; mermaid/table use a custom 4px track.
  assert.match(css, /::-webkit-scrollbar \{ width: 0; height: 0; display: none; \}/);
  assert.match(css, /\.onyx-hscroll \{/);
  assert.match(css, /height: 4px/);
  assert.match(css, /is-scrollable:not\(\.at-end\)::after/);
  assert.match(css, /is-scrollable:not\(\.at-start\)::before/);
  // Fades and the custom track are pinned to the visible edges via --onyx-sl.
  assert.match(css, /left: calc\(var\(--onyx-sl, 0px\) \+ 100% - 2\.2em\)/);
  assert.match(css, /left: var\(--onyx-sl, 0px\)/);
  assert.match(css, /padding-bottom: 8px/);
  // Lightbox button is a real control, hidden until hover.
  assert.match(css, /visibility: hidden/);
  assert.match(css, /\.mermaid:hover \.onyx-zoom-hint/);
  assert.match(css, /cursor: zoom-in/);
  assert.match(css, /#onyx-lightbox/);
  assert.match(css, /\.onyx-lb-backdrop/);
  assert.match(css, /\.onyx-lb-close/);
  assert.doesNotMatch(css, /up to ~25%/);
});

test('updateScrollCue marks both ends and only shows a scrollbar when content overflows', () => {
  const T = Tset();
  const calls = [];
  const el = {
    clientWidth: 100,
    scrollWidth: 100,
    scrollLeft: 0,
    className: '',
    classes: new Set(),
    classList: {
      toggle(name, on) { if (on) el.classes.add(name); else el.classes.delete(name); },
    },
    querySelector() { return null; },
    addEventListener(type) { calls.push(type); },
  };
  T.updateScrollCue(el);
  assert.equal(el.classes.has('is-scrollable'), false);
  assert.equal(el.classes.has('at-start'), true);
  assert.equal(el.classes.has('at-end'), true);
  assert.deepEqual(calls, []);

  el.scrollWidth = 300;
  el.scrollLeft = 100;
  T.updateScrollCue(el);
  assert.equal(el.classes.has('is-scrollable'), true);
  assert.equal(el.classes.has('at-start'), false);
  assert.equal(el.classes.has('at-end'), false);
  assert.deepEqual(calls, ['scroll']);

  el.scrollLeft = 0;
  T.updateScrollCue(el);
  assert.equal(el.classes.has('at-start'), true);
  assert.equal(el.classes.has('at-end'), false);

  el.scrollLeft = 200;
  T.updateScrollCue(el);
  assert.equal(el.classes.has('at-start'), false);
  assert.equal(el.classes.has('at-end'), true);
});

test('bleedSide caps at 8rem and leaves a 1.2rem gutter', () => {
  const T = Tset();
  // measure 656, viewport 980, rem 16: side = min(128, (980-656)/2 - 19.2) = 128
  assert.equal(T.bleedSide(656, 980, 16), 128);
  // already close to the pane: little or no bleed
  assert.equal(T.bleedSide(900, 980, 16), Math.min(128, Math.max(0, (980-900)/2 - 19.2)));
  assert.ok(T.bleedSide(900, 980, 16) < 40);
  assert.equal(T.bleedSide(980, 980, 16), 0);
});

test('applyBleed is symmetric and never exceeds the visible room on either side', () => {
  const T = Tset();
  const el = {
    style: {},
    getBoundingClientRect() { return { left: 40, right: 840, width: 800, height: 100, top: 0, bottom: 100 }; }
  };
  // Desired bleed for measure 800 in a 1000px pane is min(128, (1000-800)/2 - 19.2) = 80.8,
  // but the left only has 40 - 19.2 = 20.8px before the gutter. Use that on both sides.
  const bled = T.applyBleed(el, 800, 1000);
  assert.ok(Math.abs((el.style.marginLeft && parseFloat(el.style.marginLeft)) + 20.8) < 1e-6);
  assert.equal(el.style.marginLeft, el.style.marginRight);
  assert.ok(Math.abs(bled - (800 + 2 * 20.8)) < 1e-6);
  const room = T.bleedRoom(el, 1000, 16);
  // After applyBleed the box is still reported at the unbled rect we stubbed.
  assert.ok(Math.abs(room.left - 20.8) < 1e-6);
  assert.ok(room.right > room.left);
});

test('overflowing mermaid and tables start at scrollLeft 0, not centered', () => {
  const js = fs.readFileSync(path.join(web, 'reader.js'), 'utf8');
  assert.doesNotMatch(js, /scrollLeft\s*=\s*max\s*\/\s*2/);
  assert.match(js, /node\.scrollLeft = 0/);
});

test('updateScrollCue pins overlay offset to the wrap scrollLeft', () => {
  const T = Tset();
  const props = {};
  const el = {
    clientWidth: 100,
    scrollWidth: 300,
    scrollLeft: 80,
    className: '',
    classes: new Set(),
    classList: { toggle(name, on) { if (on) el.classes.add(name); else el.classes.delete(name); } },
    querySelector() { return null; },
    addEventListener() {},
    style: { setProperty(k, v) { props[k] = v; } },
  };
  T.updateScrollCue(el);
  assert.equal(props['--onyx-sl'], '80px');
  el.scrollLeft = 0;
  T.updateScrollCue(el);
  assert.equal(props['--onyx-sl'], '0px');
});

// --- OpenDyslexic typeface ----------------------------------------------------

test('OpenDyslexic @font-face declares all four cuts with real weights, styles, and size-adjust', () => {
  const css = fs.readFileSync(path.join(web, 'reader.css'), 'utf8');
  const faces = [...css.matchAll(/@font-face\s*\{[^}]*OpenDyslexic[^}]*\}/g)].map(m => m[0]);
  assert.equal(faces.length, 4);
  const src = f => (f.match(/OpenDyslexic-(\w+)\.woff2/) || [])[1];
  const by = Object.fromEntries(faces.map(f => [src(f), f]));
  assert.ok(by.Regular && by.Bold && by.Italic && by.BoldItalic);
  assert.match(by.Regular, /font-style:\s*normal/);
  assert.match(by.Regular, /font-weight:\s*100 500/);
  assert.match(by.Bold, /font-style:\s*normal/);
  assert.match(by.Bold, /font-weight:\s*600 900/);
  assert.match(by.Italic, /font-style:\s*italic/);
  assert.match(by.Italic, /font-weight:\s*100 500/);
  assert.match(by.BoldItalic, /font-style:\s*italic/);
  assert.match(by.BoldItalic, /font-weight:\s*600 900/);
  for (const f of faces) {
    assert.match(f, /size-adjust:\s*85%/);
    assert.match(f, /font-family:\s*'OpenDyslexic'/);
  }
});

test('OpenDyslexic typeset CSS is a full face-od style, not a Tufte overlay', () => {
  const css = fs.readFileSync(path.join(web, 'typeset.css'), 'utf8');
  assert.match(css, /body\.typeset\.face-od\s*\{/);
  assert.doesNotMatch(css, /face-dyslexic/);
  assert.match(css, /body\.typeset\.face-od\s*\{[^}]*--font-text:\s*'OpenDyslexic'/);
  assert.match(css, /body\.typeset\.face-od\s*\{[^}]*--line-height-normal:\s*1\.65/);
  const page = css.match(/body\.typeset\.face-od \.markdown-preview-view\s*\{[^}]*\}/)?.[0];
  assert.ok(page, 'preview-view rule');
  assert.match(page, /font-synthesis:\s*none/);
  assert.match(page, /font-feature-settings:\s*normal/);
  assert.match(page, /letter-spacing:\s*0/);
  assert.match(page, /word-spacing:\s*0\.05em/);
  assert.match(page, /max-width:\s*min\(var\(--file-line-width\),\s*60ch\)/);
  assert.match(page, /hyphens:\s*manual/);
  assert.match(page, /text-align:\s*left/);
  assert.match(page, /text-rendering:\s*auto/);
  assert.match(css, /body\.typeset\.face-od \.markdown-preview-view :is\(code, pre, kbd, \.tag\)\s*\{[^}]*font-family:\s*var\(--font-monospace\)/);
  assert.match(css, /body\.typeset\.face-od \.lead-in\s*\{[^}]*font-weight:\s*700/);
});

test('typesetClasses treats OpenDyslexic as its own face', () => {
  const C = ctx.window.Onyx.typesetClasses;
  assert.equal(typeof C, 'function');
  assert.equal(C({ on: true, face: 'od' }).trim(), 'typeset face-od');
  assert.equal(C({ on: true, face: 'od', onum: true, hyphens: true, justify: true }).trim(), 'typeset face-od');
  assert.equal(C({ on: true, face: 'et', onum: true, hyphens: true }).trim(), 'typeset onum hyph face-et');
  assert.equal(C({ on: true, face: 'lm', onum: true, hyphens: false }).trim(), 'typeset onum');
  assert.equal(C({ on: false, face: 'od' }).trim(), '');
  assert.equal(C({ on: true, face: 'od', print: true }).trim(), 'typeset face-od print');
  // a leftover dyslexic flag still selects the OpenDyslexic face
  assert.equal(C({ on: true, face: 'lm', dyslexic: true }).trim(), 'typeset face-od');
});

test('rich diffs wrap inserts and deletes at word level', () => {
  const out = ctx.window.Onyx._diffHTML([
    { op: 'change', kind: 'paragraph', markdown: 'The slow fox.\n', spans: [
      { op: 'same', text: 'The ' },
      { op: 'delete', text: 'quick' },
      { op: 'insert', text: 'slow' },
      { op: 'same', text: ' fox.' },
    ]},
  ]);
  assert.match(out, /<del class="onyx-diff-del">quick<\/del>/);
  assert.match(out, /<ins class="onyx-diff-ins">slow<\/ins>/);
  assert.match(out, /<p>/);
});

test('rich diffs render mermaid and tables as whole blocks', () => {
  const mer = ctx.window.Onyx._diffHTML([
    { op: 'delete', kind: 'mermaid', markdown: '```mermaid\ngraph TD\n  A-->B\n```\n' },
    { op: 'insert', kind: 'mermaid', markdown: '```mermaid\ngraph TD\n  A-->C\n```\n' },
  ]);
  assert.match(mer, /onyx-diff-del-block/);
  assert.match(mer, /onyx-diff-ins-block/);
  assert.match(mer, /pre class="mermaid"/);
  const table = ctx.window.Onyx._diffHTML([
    { op: 'insert', kind: 'table', markdown: '| a | b |\n| - | - |\n| 1 | 2 |\n' },
  ]);
  assert.match(table, /onyx-diff-ins-block/);
  assert.match(table, /<table>/);
});

test('rich diffs keep heading markup around an inline change', () => {
  const out = ctx.window.Onyx._diffHTML([
    { op: 'change', kind: 'heading', level: 2, markdown: '## Hello there\n', spans: [
      { op: 'same', text: 'Hello ' },
      { op: 'delete', text: 'world' },
      { op: 'insert', text: 'there' },
    ]},
  ]);
  assert.match(out, /<h2>/);
  assert.match(out, /<del class="onyx-diff-del">world<\/del>/);
  assert.match(out, /<ins class="onyx-diff-ins">there<\/ins>/);
});

test('tags: nested and Unicode, links to the tag; numbers and trailing slashes are not', () => {
  const out = html('see #area/health/sleep and #café and #📚 but not #2024, end #a/b/\n');
  assert.match(out, /<a class="tag" data-tag="area\/health\/sleep">#area\/health\/sleep<\/a>/);
  assert.match(out, /data-tag="café"/);
  assert.match(out, /data-tag="📚"/);
  assert.doesNotMatch(out, /data-tag="2024"/);
  assert.match(out, /<a class="tag" data-tag="a\/b">#a\/b<\/a>\//);
});

test('rich diffs render a control for collapsed unchanged stretches', () => {
  const out = ctx.window.Onyx._diffHTML([
    { op: 'collapsed', kind: 'paragraph', markdown: '', count: 12, index: 3 },
  ]);
  assert.match(out, /onyx-diff-expand/);
  assert.match(out, /data-index="3"/);
  assert.match(out, /Show 12 unchanged lines/);
});

test('outline heading scroll lands below the chrome inset with a gap, and spy uses the same offset', () => {
  const O = ctx.window.Onyx;
  assert.equal(O._outlineGap, 20);
  // heading border-box at 100, scrollY 200, offset 66 (46 fade + 20) => 234
  assert.equal(O._headingScrollY(100, 200, 66), 234);
  // Round so a fractional short landing cannot hide the heading under the fade.
  assert.equal(O._headingScrollY(100.4, 200, 66), 234);
  O.setChromeInset(46);
  assert.equal(O._outlineOffset(), 66);
  O.setChromeInset(0);
  assert.equal(O._outlineOffset(), 20);
  // After landing, heading top is 66. Spy threshold is offset+2 = 68.
  // The heading stays active; a next heading past the slop is not.
  assert.equal(O._outlineHysteresis, 2);
  assert.equal(O._activeOutlineLine([{top: 66, line: 10}, {top: 69, line: 20}], 66), 10);
  // A heading at offset+2 still counts; subpixel just past the landing stays selected.
  assert.equal(O._activeOutlineLine([{top: 68, line: 10}, {top: 90, line: 20}], 66), 10);
  assert.equal(O._activeOutlineLine([{top: 66.5, line: 10}, {top: 90, line: 20}], 66), 10);
  // After a correct landing (heading top = 66), the 48px reading anchor
  // has not reached the heading yet and would fall back to the title.
  assert.equal(O._activeOutlineLine([{top: 66, line: 10}, {top: 80, line: 20}], 66), 10);
  assert.equal(O._activeOutlineLine([{top: 66, line: 10}, {top: 80, line: 20}], 48), 0);
  // Nothing has reached the line yet: stay on the title (line 0).
  assert.equal(O._activeOutlineLine([{top: 80, line: 10}], 66), 0);
});

test('outline heading list skips fallback titles, embeds, callouts, and blockquotes', () => {
  const O = ctx.window.Onyx;
  const el = (opts = {}) => {
    const classes = new Set((opts.class || '').split(/\s+/).filter(Boolean));
    const ancestors = new Set(opts.ancestors || []);
    return {
      classList: { contains: (c) => classes.has(c) },
      closest: (sel) => ancestors.has(sel) ? {} : null,
    };
  };
  assert.equal(O._isOutlineHeading(el()), true);
  assert.equal(O._isOutlineHeading(el({ class: 'fallback-title' })), false);
  assert.equal(O._isOutlineHeading(el({ ancestors: ['.markdown-embed'] })), false);
  assert.equal(O._isOutlineHeading(el({ ancestors: ['.callout'] })), false);
  assert.equal(O._isOutlineHeading(el({ ancestors: ['blockquote'] })), false);
  assert.equal(O._isOutlineHeading(el({ ancestors: ['.footnotes'] })), false);
  assert.equal(O._isOutlineHeading(el({ ancestors: ['.kanban'] })), false);
});

test('scroll-spy walking a long note picks the last outline heading at or above the landing offset', () => {
  const O = ctx.window.Onyx;
  const offset = 66;
  // Absolute tops before any scroll: leading H1, then a run of sections.
  const items = [
    { top: 0, line: 0, title: 'Home' },
    { top: 200, line: 10, title: 'The Proprietor' },
    { top: 450, line: 24, title: 'Morning' },
    { top: 700, line: 38, title: 'Afternoon' },
    { top: 960, line: 52, title: 'The Library' },
    { top: 1210, line: 66, title: 'Coda' },
  ];
  const at = (scroll) => items.map(it => ({ top: it.top - scroll, line: it.line }));
  // Before the title has reached the landing line, stay on the title (line 0).
  // Once its top is 0 it is already at/above offset+1? 0 <= 67, so line 0 — the title.
  assert.equal(O._activeOutlineLine(at(0), offset), 0);
  // Land The Proprietor at the outline offset: top 200 - scroll = 66 => scroll 134.
  assert.equal(O._activeOutlineLine(at(200 - offset), offset), 10);
  // A few pixels later, still Proprietor (next heading is still below the line).
  assert.equal(O._activeOutlineLine(at(200 - offset + 20), offset), 10);
  // Morning lands.
  assert.equal(O._activeOutlineLine(at(450 - offset), offset), 24);
  // Midway through Afternoon, still Afternoon.
  assert.equal(O._activeOutlineLine(at(700 - offset + 80), offset), 38);
  // The Library, then Coda, then past the last heading (Coda stays active).
  assert.equal(O._activeOutlineLine(at(960 - offset), offset), 52);
  assert.equal(O._activeOutlineLine(at(1210 - offset), offset), 66);
  assert.equal(O._activeOutlineLine(at(1210 - offset + 400), offset), 66);
});

test('a heading at the top of the view followed by a tall table is active, not the previous section', () => {
  const O = ctx.window.Onyx;
  const offset = 66; // fade 46 + gap 20
  const margin = 40;  // h2 margin-top: 2em, about this in the reader
  // Connection Map shape: The Network, then Strongest Pairs, then a tall table
  // (Bridge Pages is far below). Strongest Pairs' text sits just under the fade
  // (border-box top 86) so the heading looks like it is at the top of the view.
  // Using the border-box against offset+1 (86 <= 67) would keep The Network.
  const network = { top: O._headingSpyTop(-180, margin), line: 89 };
  const pairs = { top: O._headingSpyTop(86, margin), line: 115 };
  const bridge = { top: O._headingSpyTop(900, margin), line: 140 };
  assert.equal(O._headingSpyTop(86, margin), 46);
  assert.equal(O._activeOutlineLine([network, pairs, bridge], offset), 115);
  // A heading already at the top of the view (border-box at 0) must count.
  assert.equal(O._activeOutlineLine([
    { top: O._headingSpyTop(-200, margin), line: 89 },
    { top: O._headingSpyTop(0, margin), line: 115 },
    { top: O._headingSpyTop(900, margin), line: 140 },
  ], offset), 115);
  // Border-box just below the fade, still at the top of the readable view.
  assert.equal(O._activeOutlineLine([
    { top: O._headingSpyTop(-200, margin), line: 89 },
    { top: O._headingSpyTop(50, margin), line: 115 },
    { top: O._headingSpyTop(900, margin), line: 140 },
  ], offset), 115);
  // Not yet: the heading's margin-box is still below the landing line.
  assert.equal(O._activeOutlineLine([
    { top: O._headingSpyTop(-180, margin), line: 89 },
    { top: O._headingSpyTop(200, margin), line: 115 },
    { top: O._headingSpyTop(900, margin), line: 140 },
  ], offset), 89);
});
