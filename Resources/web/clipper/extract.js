// Onyx web clipper: run after Readability.js in a loaded page. Returns a JSON string with the
// readable article (as XHTML) and the page's metadata. See Sources/Onyx/WebClipper.swift.
(() => {
  const meta = (...names) => {
    for (const n of names) {
      const e = document.querySelector(`meta[name="${n}" i], meta[property="${n}" i], meta[itemprop="${n}" i]`);
      if (e && e.content && e.content.trim()) return e.content.trim();
    }
    return '';
  };
  // JSON-LD: author names and dates many news sites only publish there.
  let ld = {};
  for (const s of document.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      let j = JSON.parse(s.textContent);
      const all = [].concat(j['@graph'] || j);
      const art = all.find(x => x && /Article|Posting|Report|WebPage/.test([].concat(x['@type'] || '').join(' ')));
      if (art) { ld = art; break; }
    } catch (_) {}
  }
  const ldAuthor = [].concat(ld.author || []).map(a => typeof a === 'string' ? a : (a && a.name) || '').filter(Boolean).join(', ');
  const url = (document.querySelector('link[rel="canonical"]') || {}).href || location.href;

  const doc = document.cloneNode(true);
  // Keep code languages (Readability strips classes) and resolve lazy images before it runs.
  for (const pre of doc.querySelectorAll('pre')) {
    const c = [pre.className, ...[...pre.querySelectorAll('code')].map(x => x.className)].join(' ');
    const m = c.match(/(?:language-|lang-|highlight-source-)([\w+#.-]+)/i);
    if (m) pre.setAttribute('data-onyx-lang', m[1]);
  }
  // Wiki "[edit]" links, skip links and similar page furniture.
  doc.querySelectorAll('.mw-editsection, .mw-jump-link, [class*="skip-link"], [aria-hidden="true"]:not(img)').forEach(e => e.remove());
  const live = document.images;
  doc.querySelectorAll('img').forEach((img, i) => {
    const l = live[i];
    if (l && l.currentSrc && !l.currentSrc.startsWith('data:')) img.setAttribute('src', l.currentSrc);
  });
  let article = null;
  try { article = new Readability(doc, { charThreshold: 200 }).parse(); } catch (_) {}
  const wrap = document.createElement('div');
  wrap.innerHTML = article && article.content ? article.content : document.body.innerHTML;
  wrap.querySelectorAll('[src],[href]').forEach(e => {
    for (const k of ['src', 'href']) {
      if (!e.hasAttribute(k)) continue;
      try { e.setAttribute(k, new URL(e.getAttribute(k), location.href).href); } catch (_) {}
    }
  });
  return JSON.stringify({
    url,
    title: (article && article.title) || meta('og:title', 'twitter:title') || document.title || '',
    byline: (article && article.byline) || meta('author', 'article:author', 'parsely-author', 'sailthru.author') || ldAuthor,
    site: (article && article.siteName) || meta('og:site_name', 'application-name') || '',
    description: meta('description', 'og:description', 'twitter:description') || (article && article.excerpt) || '',
    published: (article && article.publishedTime) || meta('article:published_time', 'datePublished', 'date', 'parsely-pub-date', 'dc.date') || ld.datePublished || '',
    readable: !!(article && article.content),
    html: new XMLSerializer().serializeToString(wrap),
  });
})()
