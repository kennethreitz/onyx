// Delimiter parsing for Obsidian-style $inline$ / $$display$$ math.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const web = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../Resources/web');
const window = {};
const ctx = vm.createContext({ window, globalThis: window, self: window, console });
vm.runInContext(fs.readFileSync(path.join(web, 'math.js'), 'utf8'), ctx, { filename: 'math.js' });
const M = ctx.window.OnyxMath || ctx.OnyxMath;
assert.ok(M, 'OnyxMath should load');

const hits = (src) => M.find(src).map(h => ({ tex: String(h.tex), display: Boolean(h.display) }));
// JSON: values may come from a vm realm, and deepStrictEqual treats those as unequal.
const eq = (src, expected) => assert.equal(JSON.stringify(hits(src)), JSON.stringify(expected));


test('inline $...$ and display $$...$$', () => {
  eq('see $x$ here',  [{ tex: 'x', display: false }]);
  eq('$$x+y$$',  [{ tex: 'x+y', display: true }]);
  eq('a $x$ and $$y$$ z',  [
    { tex: 'x', display: false },
    { tex: 'y', display: true },
  ]);
});

test('multi-line $$ blocks', () => {
  const src = 'before\n$$\nE = mc^2\n$$\nafter';
  eq(src,  [{ tex: '\nE = mc^2\n', display: true }]);
  const aligned = '$$\n\\begin{aligned}\na &= b \\\\\nc &= d\n\\end{aligned}\n$$';
  assert.equal(hits(aligned).length, 1);
  assert.equal(hits(aligned)[0].display, true);
  assert.match(hits(aligned)[0].tex, /\\begin\{aligned\}/);
});

test('no space right inside the delimiters (Obsidian)', () => {
  eq('this is $ x$ not math',  []);
  eq('this is $x $ not math',  []);
  eq('this is $ x $ not math',  []);
  eq('$$ x $$ is not tight',  []);
  eq('$$x$$ is tight',  [{ tex: 'x', display: true }]);
});

test('currency like $5 and $10 is not math', () => {
  eq('it costs $5 and $10 today',  []);
  eq('only $20',  []);
  eq('the $5$10 split',  []); // closing $ followed by a digit
});

test('escaped dollars are not delimiters', () => {
  eq('a \\$x\\$ b',  []);
  eq('price is \\$5',  []);
  // A backslash before the first $ cancels it; the second $ may open later.
  eq('an escaped \\$ and $x$',  [{ tex: 'x', display: false }]);
  // Even number of backslashes: the $ is not escaped, so \\$x$ is a backslash plus math.
  eq('\\\\$x$',  [{ tex: 'x', display: false }]);
});

test('math inside code spans or blocks is left alone', () => {
  eq('use `$x$` in code',  []);
  eq('`` $x$ ``',  []);
  eq('```\n$x$\n$$\ny$$\n```\n',  []);
  eq('~~~\n$x$\n~~~\n',  []);
  eq('plain\n\n    $indented$\n\nlater $z$',  [{ tex: 'z', display: false }]);
});

test('math still works next to code', () => {
  eq('`a` and $x$',  [{ tex: 'x', display: false }]);
  eq('```\ncode\n```\n\n$x$',  [{ tex: 'x', display: false }]);
});

test('underscores and other TeX stay inside the span', () => {
  eq('see $a_1 + b^2$',  [{ tex: 'a_1 + b^2', display: false }]);
});

test('inline math cannot wrap a line break', () => {
  eq('$x\ny$',  []);
});

test('empty delimiters are not math', () => {
  eq('$$',  []);
  eq('$$$$',  []);
});

test('protect keeps newline counts so later lines stay aligned', () => {
  const src = 'a\n$$\nE=mc^2\n$$\nb';
  const { text, slots } = M.protect(src);
  assert.equal(slots.length, 1);
  assert.equal((text.match(/\n/g) || []).length, (src.match(/\n/g) || []).length);
  assert.match(text, /§§ONYXMATH0§§/);
  assert.doesNotMatch(text, /E=mc\^2/);
});
