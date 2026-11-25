// Every icon the Safari extension's manifest names is committed (scripts/make-extension-icons.swift).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const res = join(dirname(fileURLToPath(import.meta.url)), '../../Extensions/Safari/Resources');
const manifest = JSON.parse(readFileSync(join(res, 'manifest.json'), 'utf8'));

test('manifest icons and toolbar icons exist', () => {
  const paths = [...Object.values(manifest.icons), ...Object.values(manifest.action.default_icon)];
  assert.ok(paths.length >= 16);
  for (const p of paths) assert.ok(existsSync(join(res, p)), p);
});

test('toolbar uses the monochrome glyph, settings the full-color icon', () => {
  for (const p of Object.values(manifest.action.default_icon)) assert.match(p, /toolbar-/);
  for (const p of Object.values(manifest.icons)) assert.match(p, /icon-/);
});

test('clip shortcut is ⌃⇧O on the Mac, nothing Safari already uses', () => {
  const key = manifest.commands._execute_action.suggested_key;
  assert.equal(key.mac, 'MacCtrl+Shift+O');
  // ⇧⌘R is Safari's Reader; ⌘-based combos mostly belong to Safari.
  assert.doesNotMatch(key.mac, /Command|Ctrl\+Shift\+R/);
});
