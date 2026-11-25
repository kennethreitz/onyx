// Safari "Clip to Onyx" background script, run against a stub `browser` API.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const listeners = {};
const sent = [];
const updated = [];
let nativeReply = { ok: true };
let pageResult = { url: 'https://ex.com/p', title: 'Page', selection: '<div>sel</div>' };
const ev = name => ({ addListener: fn => { listeners[name] = fn; } });
globalThis.browser = {
  action: { onClicked: ev('action') },
  runtime: {
    onInstalled: ev('installed'), onStartup: ev('startup'),
    sendNativeMessage: async (id, msg) => { sent.push([id, msg]); if (nativeReply instanceof Error) throw nativeReply; return nativeReply; },
  },
  scripting: { executeScript: async () => [{ result: pageResult }] },
  contextMenus: { removeAll: cb => cb(), create: () => {}, onClicked: ev('menu') },
  tabs: { update: async (id, o) => { updated.push([id, o]); } },
};
const require = createRequire(import.meta.url);
const bg = require('../../Extensions/Safari/Resources/background.js');

test('toolbar click sends the page and selection to the native handler', async () => {
  sent.length = 0; updated.length = 0; nativeReply = { ok: true };
  await listeners.action({ id: 7, url: 'https://ex.com/p', title: 'Page' });
  assert.equal(sent.length, 1);
  assert.deepEqual(sent[0][1], pageResult);
  assert.equal(updated.length, 0);
});

test('without the native handler it opens onyx://clip in the tab', async () => {
  sent.length = 0; updated.length = 0; nativeReply = new Error('no handler');
  await listeners.action({ id: 7, url: 'https://ex.com/p', title: 'Page' });
  assert.equal(updated.length, 1);
  assert.equal(updated[0][1].url, 'onyx://clip?url=https%3A%2F%2Fex.com%2Fp&title=Page&selection=%3Cdiv%3Esel%3C%2Fdiv%3E');
});

test('Clip Link sends only the link', async () => {
  sent.length = 0; nativeReply = { ok: true };
  await listeners.menu({ menuItemId: 'onyx-clip-link', linkUrl: 'https://ex.com/other' }, { id: 1 });
  assert.deepEqual(sent[0][1], { url: 'https://ex.com/other' });
});

test('clipURL encodes + & = #', () => {
  assert.equal(bg.clipURL({ url: 'https://e.com/?a=1&b=2#c', title: 'A + B' }),
    'onyx://clip?url=https%3A%2F%2Fe.com%2F%3Fa%3D1%26b%3D2%23c&title=A%20%2B%20B');
});
