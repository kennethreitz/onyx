// Generates crypto test vectors for OnyxSync by running a faithful transcription of
// Obsidian 1.15.1's sync crypto (app.js; same code ships in obsidian-headless 0.0.14 cli.js)
// on Node's WebCrypto. Run: node scripts/obsidian-sync-vectors.mjs > Tests/OnyxSyncTests/Resources/obsidian-sync-vectors.json
import nodeCrypto from "node:crypto";
const js = globalThis.crypto.subtle;
const enc = s => new TextEncoder().encode(s).buffer;           // Fo
const hex = b => Buffer.from(new Uint8Array(b)).toString("hex"); // Rs
const unhex = h => new Uint8Array(Buffer.from(h, "hex")).buffer; // J2

// ---- scrypt (BT): NFKC both, N=32768 r=8 p=1 dkLen=32, maxmem = 128*N*r*2
async function deriveKey(password, salt) {
  password = password.normalize("NFKC"); salt = salt.normalize("NFKC");
  const N = 32768, r = 8, p = 1;
  return new Promise((res, rej) => nodeCrypto.scrypt(Buffer.from(password, "utf8"), Buffer.from(salt, "utf8"), 32,
    { N, r, p, maxmem: 128 * N * r * 2 }, (e, k) => e ? rej(e) : res(new Uint8Array(k).buffer)));
}
// ---- AES-SIV (Rk / Ok / Fk / Pk / br), transcribed
const SIZE = 16;
class Block { constructor() { this.data = new Uint8Array(SIZE); } clear() { this.data.fill(0); }
  clone() { const t = new Block(); t.data.set(this.data); return t; }
  dbl() { let c = 0; for (let e = SIZE - 1; e >= 0; e--) { const i = this.data[e] >>> 7 & 255; this.data[e] = this.data[e] << 1 | c; c = i; }
    this.data[SIZE - 1] ^= c ? 135 : 0; } }
const xorInto = (o, t) => { for (let e = 0; e < t.length; e++) o[e] ^= t[e]; };
class Ctr { static async importKey(ikm, salt) { return Object.assign(new Ctr(), { key: await js.deriveKey({ name: "HKDF", salt, info: enc("ObsidianAesSivEnc"), hash: "SHA-256" }, ikm, { name: "AES-CTR", length: 256 }, false, ["encrypt"]) }); }
  async encryptCtr(counter, data) { return new Uint8Array(await js.encrypt({ name: "AES-CTR", counter, length: 16 }, this.key, data)); } }
class Prf { static async importKey(ikm, salt) { const p = new Prf(); p.key = await js.deriveKey({ name: "HKDF", salt, info: enc("ObsidianAesSivMac"), hash: "SHA-256" }, ikm, { name: "AES-CBC", length: 256 }, false, ["encrypt"]); p.iv = new Block(); return p; }
  async encryptBlock(b) { const o = await js.encrypt({ name: "AES-CBC", iv: this.iv.data }, this.key, b.data); b.data.set(new Uint8Array(o, 0, SIZE)); } }
class Cmac { constructor(c, k1, k2) { this.c = c; this.k1 = k1; this.k2 = k2; this.pos = 0; this.fin = false; this.buf = new Block(); }
  static async importKey(ikm, salt) { const c = await Prf.importKey(ikm, salt); const r = new Block(); await c.encryptBlock(r); r.dbl(); const n = r.clone(); n.dbl(); return () => new Cmac(c, r, n); }
  async update(t) { let e = SIZE - this.pos, i = 0, r = t.length;
    if (r > e) { for (let n = 0; n < e; n++) this.buf.data[this.pos + n] ^= t[n]; r -= e; i += e; await this.c.encryptBlock(this.buf); this.pos = 0; }
    for (; r > SIZE;) { for (let n = 0; n < SIZE; n++) this.buf.data[n] ^= t[i + n]; r -= SIZE; i += SIZE; await this.c.encryptBlock(this.buf); }
    for (let n = 0; n < r; n++) this.buf.data[this.pos++] ^= t[i + n]; }
  async finish() { if (!this.fin) { const t = this.pos < SIZE ? this.k2 : this.k1; xorInto(this.buf.data, t.data); if (this.pos < SIZE) this.buf.data[this.pos] ^= 128; await this.c.encryptBlock(this.buf); this.fin = true; } return this.buf.data; } }
const clearBits = o => { o[o.length - 8] &= 127; o[o.length - 4] &= 127; };
class Siv { static async importKey(ikm, salt) { const s = new Siv(); s.cmac = await Cmac.importKey(ikm, salt); s.ctr = await Ctr.importKey(ikm, salt); return s; }
  async s2v(t) { let e = this.cmac(); const i = new Block(), r = new Block(); await e.update(i.data); r.data.set(await e.finish()); e = this.cmac(); i.clear();
    if (t.length >= SIZE) { const n = t.length - SIZE; i.data.set(t.subarray(n)); await e.update(t.subarray(0, n)); } else { i.data.set(t); i.data[t.length] = 128; r.dbl(); }
    xorInto(i.data, r.data); await e.update(i.data); return e.finish(); }
  async seal(t) { const out = new Uint8Array(SIZE + t.length), v = await this.s2v(t); out.set(v); clearBits(v); out.set(await this.ctr.encryptCtr(v, t), SIZE); return out; } }
// ---- providers (b9 = v0, v9 = v2/v3)
async function gcmEncrypt(data, key, iv) { const ct = await js.encrypt({ name: "AES-GCM", iv }, key, data); const o = new Uint8Array(12 + ct.byteLength); o.set(new Uint8Array(iv)); o.set(new Uint8Array(ct), 12); return o.buffer; }
async function provider(version, key, salt) {
  if (version === 0) { const ck = await js.importKey("raw", key, "AES-GCM", false, ["encrypt", "decrypt"]);
    return { keyHash: hex(await js.digest("SHA-256", key)), det: async s => { const e = enc(s); const iv = new Uint8Array(await js.digest("SHA-256", e), 0, 12); return hex(await gcmEncrypt(e, ck, iv)); }, ck }; }
  const ikm = await js.importKey("raw", key, "HKDF", false, ["deriveKey"]); const n = enc(salt);
  const kh = await js.deriveKey({ name: "HKDF", salt: n, info: enc("ObsidianKeyHash"), hash: "SHA-256" }, ikm, { name: "AES-CBC", length: 256 }, true, ["encrypt"]);
  const siv = await Siv.importKey(ikm, n);
  const ck = await js.deriveKey({ name: "HKDF", salt: new Uint8Array(), info: enc("ObsidianAesGcm"), hash: "SHA-256" }, ikm, { name: "AES-GCM", length: 256 }, true, ["encrypt", "decrypt"]);
  return { keyHash: hex(await js.exportKey("raw", kh)), det: async s => hex(await siv.seal(new Uint8Array(enc(s)))), ck, gcmRaw: hex(await js.exportKey("raw", ck)) };
}
const sha256hex = async b => hex(await js.digest("SHA-256", b));

const cases = [
  { password: "correct horse battery staple", salt: "0123456789abcdef0123456789abcdef" },
  { password: "Onyx ✦ päßwörd", salt: "fedcba9876543210fedcba9876543210" },
  { password: "ｏｎｙｘ", salt: "deadbeefdeadbeefdeadbeefdeadbeef" }, // NFKC folds fullwidth
];
const strings = ["", "a", "Daily/2026-11-20.md", "exactly16bytes!!", "Knowledge/Hebrew Letters/Aleph.md", "Writing/Poetry/AI-Written/ünïcödé — 詩.md",
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "x".repeat(1100)];
const out = { generator: "scripts/obsidian-sync-vectors.mjs", source: "Obsidian 1.15.1 app.js (sync crypto)", scrypt: { N: 32768, r: 8, p: 1, dkLen: 32 }, cases: [] };
for (const c of cases) {
  const key = await deriveKey(c.password, c.salt);
  const entry = { ...c, key: hex(key), versions: {} };
  for (const v of [0, 3]) {
    const p = await provider(v, key, c.salt);
    const det = []; for (const s of strings) det.push({ plain: s, cipher: await p.det(s) });
    const iv = new Uint8Array(12).map((_, i) => i + 1);
    const content = enc("# Hello from Onyx\n\nSynced, sealed, delivered.\n");
    const gcm = hex(await gcmEncrypt(content, p.ck, iv));
    entry.versions[v] = { keyHash: p.keyHash, gcmKey: p.gcmRaw ?? null, deterministic: det, content: { plainHex: hex(content), iv: hex(iv), cipher: gcm, sha256: await sha256hex(content) } };
  }
  out.cases.push(entry);
}
// CTR 16-bit wrap probe: find a short plaintext (2 blocks) whose SIV's low 16 bits are 0xFFFF so WebCrypto's
// length:16 counter wraps instead of carrying. Proves our Swift CTR matches WebCrypto, not RFC 5297.
{ const key = unhex(out.cases[0].key); const ikm = await js.importKey("raw", key, "HKDF", false, ["deriveKey"]);
  const siv = await Siv.importKey(ikm, enc(out.cases[0].salt)); let found = null;
  for (let i = 0; i < 400000 && !found; i++) { const s = `wrap-probe-${i}-padding-to-two-blocks`; const sealed = await siv.seal(new Uint8Array(enc(s)));
    if (sealed[14] === 0xff && sealed[15] === 0xff) found = { plain: s, cipher: hex(sealed) }; }
  out.ctrWrap = found; }
console.log(JSON.stringify(out, null, 2));
