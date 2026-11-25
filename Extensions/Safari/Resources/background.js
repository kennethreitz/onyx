// Clip to Onyx: the toolbar button and context menu items gather the page (or selection)
// and hand it to Onyx through the extension's native handler, which opens onyx://clip.
const api = globalThis.browser ?? globalThis.chrome;

// Runs in the page (like the bookmarklet in docs/web-clipper.md): URL, title, metadata, and
// the selection as XHTML with absolute links. No selection → Onyx fetches the page itself.
function collectPage() {
  const m = (...names) => {
    for (const k of names) {
      const e = document.querySelector(`meta[name="${k}"],meta[property="${k}"],meta[itemprop="${k}"]`);
      if (e && e.content) return e.content.trim();
    }
    return '';
  };
  const out = { url: location.href, title: m('og:title') || document.title };
  const a = m('author', 'article:author', 'parsely-author', 'sailthru.author');
  if (a && !/^https?:/.test(a)) out.author = a;
  out.description = m('description', 'og:description');
  out.published = m('article:published_time', 'datePublished', 'date', 'parsely-pub-date');
  out.site = m('og:site_name');
  const g = getSelection();
  if (g && g.rangeCount && !g.isCollapsed) {
    const w = document.createElement('div');
    for (let i = 0; i < g.rangeCount; i++) w.appendChild(g.getRangeAt(i).cloneContents());
    w.querySelectorAll('img').forEach(i => { if (i.currentSrc) i.setAttribute('src', i.currentSrc); });
    w.querySelectorAll('[src],[href]').forEach(e => {
      for (const k of ['src', 'href']) {
        if (!e.hasAttribute(k)) continue;
        try { e.setAttribute(k, new URL(e.getAttribute(k), location.href).href); } catch (_) {}
      }
    });
    out.selection = new XMLSerializer().serializeToString(w);
  }
  return out;
}

function clipURL(fields) {
  const q = [];
  for (const k of ['url', 'title', 'selection', 'text', 'author', 'description', 'published', 'site']) {
    if (fields[k]) q.push(k + '=' + encodeURIComponent(fields[k]));
  }
  return 'onyx://clip?' + q.join('&');
}

async function clip(tab, override) {
  if (!tab) return;
  let fields = { url: tab.url, title: tab.title };
  if (override) {
    fields = override;
  } else {
    try {
      const [r] = await api.scripting.executeScript({ target: { tabId: tab.id }, func: collectPage });
      if (r && r.result) fields = r.result;
    } catch (_) { /* restricted page: clip by URL */ }
  }
  try {
    const reply = await api.runtime.sendNativeMessage('org.kennethreitz.onyx', fields);
    if (reply && reply.ok) return;
  } catch (_) { /* fall through */ }
  // Fallback: let Safari open the URL (it asks once whether the page may open Onyx).
  try { await api.tabs.update(tab.id, { url: clipURL(fields) }); } catch (_) {}
}

api.action.onClicked.addListener(tab => clip(tab));

function setUpMenus() {
  api.contextMenus.removeAll(() => {
    api.contextMenus.create({ id: 'onyx-clip-page', title: 'Clip Page to Onyx', contexts: ['page'] });
    api.contextMenus.create({ id: 'onyx-clip-selection', title: 'Clip Selection to Onyx', contexts: ['selection'] });
    api.contextMenus.create({ id: 'onyx-clip-link', title: 'Clip Link to Onyx', contexts: ['link'] });
  });
}
api.runtime.onInstalled.addListener(setUpMenus);
api.runtime.onStartup && api.runtime.onStartup.addListener(setUpMenus);
setUpMenus();

api.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === 'onyx-clip-link' && info.linkUrl) {
    clip(tab, { url: info.linkUrl });
  } else {
    clip(tab);
  }
});

if (typeof module === 'object') module.exports = { clipURL, collectPage };
