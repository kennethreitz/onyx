// Onyx reading view. Swift hands us a payload with every link, embed and
// dataview result already resolved; we only typeset.
(function () {
  const page = document.getElementById('page');
  let P = { links: {}, embeds: {} };
  const post = (m) => window.webkit && window.webkit.messageHandlers.onyx.postMessage(m);
  const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  function parseLink(inner) {
    let target = inner, alias = null, heading = null;
    const bar = target.indexOf('|');
    if (bar >= 0) { alias = target.slice(bar + 1); target = target.slice(0, bar); }
    if (target.endsWith('\\')) target = target.slice(0, -1);
    const hash = target.indexOf('#');
    if (hash >= 0) { heading = target.slice(hash + 1); target = target.slice(0, hash); }
    return { target: target.trim(), alias, heading };
  }

  function linkHTML(inner) {
    const l = parseLink(inner);
    const info = P.links[l.target.toLowerCase()];
    const path = info ? info.path : '';
    const unresolved = info && !path && l.target;
    let label = l.alias || (l.target ? l.target.split('/').pop() : '') + (l.heading ? (l.target ? ' › ' : '') + l.heading.replace(/^\^/, '') : '');
    if (!l.alias && !l.target && l.heading) label = l.heading;
    return `<a class="internal-link${unresolved ? ' is-unresolved' : ''}" data-path="${esc(path)}" data-target="${esc(l.target)}" data-heading="${esc(l.heading || '')}">${esc(label)}</a>`;
  }

  // Attachment embeds. Each links to Onyx's in-pane viewer (↗); audio gets a quiet player of its own.
  const fileName = (p) => String(p || '').split('/').pop();
  const openLink = (path, label) => `<a class="internal-link file-open" data-path="${esc(path)}" data-target="${esc(path)}" title="Open in Onyx">${esc(label)} ↗</a>`;
  function audioEmbedHTML(url, path) {
    return `<div class="audio-embed" data-path="${esc(path)}"><button class="ae-play" aria-label="Play"></button>` +
      `<div class="ae-track"><div class="ae-fill"></div></div><span class="ae-time">0:00</span>${openLink(path, fileName(path))}` +
      `<audio preload="metadata" src="${esc(url)}"></audio></div>`;
  }
  // Obsidian sizing: the last `|` segment of a wikilink's text or a Markdown image's alt is a size
  // when it reads `W` or `WxH` (`![[a.png|300]]`, `![[a.png|cap|300x200]]`, `![cap|300](a.png)`).
  function sizeOf(label) {
    if (label == null) return { alt: null, w: 0, h: 0 };
    const bar = label.lastIndexOf('|');
    const m = /^\s*(\d+)(?:x(\d+))?\s*$/.exec(bar >= 0 ? label.slice(bar + 1) : label);
    if (!m || !+m[1]) return { alt: label, w: 0, h: 0 };
    let alt = bar >= 0 ? label.slice(0, bar) : null;
    if (alt && alt.endsWith('\\')) alt = alt.slice(0, -1);
    return { alt, w: +m[1], h: m[2] && +m[2] ? +m[2] : 0 };
  }
  const sizeAttrs = (s) => s && s.w ? ` width="${s.w}"${s.h ? ` height="${s.h}"` : ''}` : '';
  function mediaEmbedHTML(kind, url, path, width) {
    switch (kind) {
      case 'audio': return audioEmbedHTML(url, path);
      case 'video': return `<figure class="file-embed"><video controls preload="metadata"${width || ''} src="${esc(url)}"></video><figcaption>${openLink(path, fileName(path))}</figcaption></figure>`;
      case 'pdf': return `<figure class="file-embed"><embed class="pdf-embed" src="${esc(url)}" type="application/pdf"><figcaption>${openLink(path, fileName(path))}</figcaption></figure>`;
      default: return `<img src="${esc(url)}"${width || ''} alt="${esc(fileName(path))}" data-path="${esc(path)}">`;
    }
  }
  const AUDIO_EXT = /\.(mp3|m4a|m4b|aac|wav|aiff?|caf|flac|ogg|oga|opus|3gp)$/i, VIDEO_EXT = /\.(mp4|m4v|mov|webm|mkv|ogv)$/i;
  const fmtTime = (s) => { s = Math.max(0, Math.floor(s || 0)); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = String(s % 60).padStart(2, '0'); return h ? `${h}:${String(m).padStart(2, '0')}:${x}` : `${m}:${x}`; };
  function aeSync(a) {
    const box = a.closest('.audio-embed'); if (!box) return;
    const d = isFinite(a.duration) ? a.duration : 0;
    box.querySelector('.ae-fill').style.width = d ? (100 * a.currentTime / d) + '%' : '0';
    box.querySelector('.ae-time').textContent = a.paused || !d ? (a.currentTime > 0 ? fmtTime(a.currentTime) + ' / ' : '') + fmtTime(d) : fmtTime(a.currentTime) + ' / ' + fmtTime(d);
    box.classList.toggle('is-playing', !a.paused && !a.ended);
  }
  ['loadedmetadata', 'timeupdate', 'play', 'pause', 'ended'].forEach(t => document.addEventListener(t, (e) => { if (e.target.tagName === 'AUDIO') aeSync(e.target); }, true));

  const embedDepth = { n: 0 };
  function embedHTML(inner) {
    const l = parseLink(inner);
    const e = P.embeds[l.target.toLowerCase()];
    if (!e) return linkHTML(inner);
    const sz = sizeOf(l.alias);
    switch (e.type) {
      case 'image': return `<img src="${e.url}"${sizeAttrs(sz)} alt="${esc(sz.alt || l.target)}" data-path="${esc(e.path)}" data-embed="wiki" data-embed-target="${esc(l.target)}">`;
      case 'video': return mediaEmbedHTML('video', e.url, e.path, sizeAttrs(sz));
      case 'audio': case 'pdf': return mediaEmbedHTML(e.type, e.url, e.path);
      case 'note':
        if (embedDepth.n > 1) return linkHTML(inner);
        embedDepth.n++;
        const html = withMath(stripComments(e.markdown), s => embedMarked.parse(s));
        embedDepth.n--;
        return `<div class="markdown-embed"><a class="internal-link embed-link" data-path="${esc(e.path)}" data-target="${esc(l.target)}">${esc(e.name)} ↗</a>${html}</div>`;
      default: return linkHTML(inner);
    }
  }

  const wikilink = {
    name: 'wikilink', level: 'inline',
    start(src) { const i = src.search(/!?\[\[/); return i < 0 ? undefined : i; },
    tokenizer(src) {
      const m = /^(!?)\[\[([^\[\]\n]+?)\]\]/.exec(src);
      if (m) return { type: 'wikilink', raw: m[0], embed: !!m[1], inner: m[2] };
    },
    renderer(t) { return t.embed ? embedHTML(t.inner) : linkHTML(t.inner); }
  };
  const highlight = {
    name: 'highlight', level: 'inline',
    start(src) { const i = src.indexOf('=='); return i < 0 ? undefined : i; },
    tokenizer(src) {
      const m = /^==(?=\S)([\s\S]*?\S)==/.exec(src);
      if (m) return { type: 'highlight', raw: m[0], tokens: this.lexer.inlineTokens(m[1]) };
    },
    renderer(t) { return `<mark>${this.parser.parseInline(t.tokens)}</mark>`; }
  };
  const tag = {
    name: 'tag', level: 'inline',
    start(src) { const m = src.match(/(^|\s)#[A-Za-z0-9_\-\/]*[A-Za-z_\-\/]/); return m ? m.index + m[1].length : undefined; },
    tokenizer(src) {
      const m = /^#([A-Za-z0-9_\-\/]*[A-Za-z_\-\/][A-Za-z0-9_\-\/]*)/.exec(src);
      if (m) return { type: 'tag', raw: m[0], tag: m[1] };
    },
    renderer(t) { return `<a class="tag" data-tag="${esc(t.tag)}">#${esc(t.tag)}</a>`; }
  };

  const renderer = {
    heading({ tokens, depth }) { return `<h${depth}>${this.parser.parseInline(tokens)}</h${depth}>\n`; },
    code({ text, lang }) {
      if ((lang || '').trim() === 'mermaid') return `<pre class="mermaid">${esc(text)}</pre>`;
      return `<pre><code class="language-${esc(lang || '')}">${esc(text)}</code></pre>`;
    },
    link({ href, title, tokens }) {
      const text = this.parser.parseInline(tokens);
      if (/^(https?|mailto|obsidian):/i.test(href)) return `<a class="external-link" href="${esc(href)}"${title ? ` title="${esc(title)}"` : ''}>${text}</a>`;
      const clean = decodeURIComponent(href.replace(/^\.\//, '').split('#')[0]);
      return `<a class="internal-link" data-target="${esc(clean)}" data-heading="${esc(href.split('#')[1] || '')}">${text}</a>`;
    },
    image({ href, title, text }) {
      const mdEmbed = h => { const m = P.mdembeds || {}; if (m[h]) return m[h]; try { return m[decodeURI(h)]; } catch (e) { return undefined; } };
      const src = /^(https?|data|onyx):/i.test(href) ? href : (mdEmbed(href) || P.base + href.replace(/^\.\//, ''));
      const vault = /^onyx:\/\/vault\//.test(src) ? (() => { try { return decodeURIComponent(src.slice(13)); } catch (e) { return ''; } })() : '';
      const bare = href.split(/[?#]/)[0];
      if (vault && AUDIO_EXT.test(bare)) return mediaEmbedHTML('audio', src, vault);
      const sz = sizeOf(text), alt = sz.w ? (sz.alt || '') : text;
      if (vault && VIDEO_EXT.test(bare)) return mediaEmbedHTML('video', src, vault, sizeAttrs(sz));
      if (vault && /\.pdf$/i.test(bare)) return mediaEmbedHTML('pdf', src, vault);
      const at = `${sizeAttrs(sz)} alt="${esc(alt)}"${title ? ` title="${esc(title)}"` : ''} data-embed="md" data-embed-target="${esc(href)}"`;
      if (vault) return `<img src="${esc(src)}"${at} data-path="${esc(vault)}">`;
      return `<img src="${esc(src)}"${at}>`;
    },
    blockquote({ tokens }) {
      const inner = this.parser.parse(tokens);
      const m = /^<p>\[!([\w-]+)\]([+-]?)[ \t]*([^\n<]*)(?:\n|<br>)?/.exec(inner);
      if (!m) return `<blockquote>${inner}</blockquote>\n`;
      const type = m[1].toLowerCase();
      const title = m[3].trim() || type.charAt(0).toUpperCase() + type.slice(1);
      let rest = inner.slice(m[0].length);
      rest = rest.replace(/^<\/p>\s*/, '');
      if (!rest.startsWith('<')) rest = '<p>' + rest;
      const body = `<div class="callout-content">${rest.replace(/^<p><\/p>/, '')}</div>`;
      if (m[2]) return `<details class="callout" data-callout="${type}"${m[2] === '+' ? ' open' : ''}><summary class="callout-title">${title}.</summary>${body}</details>`;
      return `<div class="callout" data-callout="${type}"><div class="callout-title">${title}.</div>${body}</div>\n`;
    },
    table(token) {
      return `<div class="table-wrap">${marked.Renderer.prototype.table.call(this, token)}</div>`;
    },
  };

  // breaks: Obsidian's default ("Strict line breaks" off): a single newline inside a paragraph
  // is a line break; blank lines still separate paragraphs. Code, tables and list structure are
  // unaffected (marked only applies it to inline text).
  const mainMarked = new marked.Marked({ gfm: true, breaks: true });
  mainMarked.use({ extensions: [wikilink, highlight, tag], renderer });
  if (window.markedFootnote) mainMarked.use(markedFootnote({ description: 'Notes', refMarkers: false }));
  const embedMarked = new marked.Marked({ gfm: true, breaks: true });
  embedMarked.use({ extensions: [wikilink, highlight, tag], renderer });

  function stripComments(md) { return md.replace(/%%[\s\S]*?%%/g, m => m.replace(/[^\n]/g, '')); }  // keep line numbers

  function withMath(md, parse) {
    if (!window.OnyxMath) return parse(md);
    const prep = window.OnyxMath.protect(md);
    return window.OnyxMath.restore(parse(prep.text), prep.slots);
  }
  function parseInlineMath(s) { return withMath(s, x => embedMarked.parseInline(x)); }


  // Source-line anchors. Each top-level block gets data-line (0-based line in the note file,
  // frontmatter included) and data-lines (how many source lines it spans), so the reader and
  // editor can hand each other "where you are" by source position rather than pixels.
  const ANCHOR = 48;   // px under the visible top that counts as the reading position (matches the editor)
  function parseWithLines(md, base) {
    const prep = window.OnyxMath ? window.OnyxMath.protect(md) : { text: md, slots: [] };
    const toks = mainMarked.lexer(prep.text);
    // marked-footnote injects a `footnotes` token at the start of the lexer
    // list and moves it to the end in walkTokens — but only in that original
    // array. We copy tokens into a new `out` list (and insert line-marker
    // tokens in front of each block), so the move never takes effect and the
    // notes section renders at the top of the page, above the title. Relocate
    // it ourselves before numbering. The definition tokens stay put (they
    // render as empty); only the collected section token is moved.
    const body = [], notes = [];
    for (const t of toks) (t.type === 'footnotes' ? notes : body).push(t);
    const out = [];
    let line = base;
    for (const t of body.concat(notes)) {
      const raw = t.raw || '';
      if (t.type !== 'space' && t.type !== 'footnotes' && raw.trim()) {
        const lead = (raw.match(/^\n*/) || [''])[0].length;
        const span = raw.replace(/^\n+/, '').replace(/\n+$/, '').split('\n').length;
        out.push({ type: 'html', block: true, pre: false, raw: '', text: `<!--L${line + lead}:${span}-->` });
      }
      out.push(t);
      line += (raw.match(/\n/g) || []).length;
    }
    out.links = toks.links;
    if (mainMarked.defaults.walkTokens) mainMarked.walkTokens(out, mainMarked.defaults.walkTokens);
    const html = mainMarked.parser(out);
    return window.OnyxMath ? window.OnyxMath.restore(html, prep.slots) : html;
  }
  function markLines() {
    const walker = document.createTreeWalker(page, NodeFilter.SHOW_COMMENT);
    const marks = [];
    while (walker.nextNode()) marks.push(walker.currentNode);
    for (const c of marks) {
      const m = /^L(\d+):(\d+)$/.exec(c.data);
      if (!m) continue;
      let el = c.nextSibling;
      while (el && el.nodeType !== 1) el = el.nextSibling;
      if (el && !el.dataset.line) { el.dataset.line = m[1]; el.dataset.lines = m[2]; }
      c.remove();
    }
  }
  function blocks() { return [...page.querySelectorAll('[data-line]')].filter(e => e.offsetParent !== null || e.getClientRects().length); }
  function topLine() {
    if (window.scrollY <= 0) return 0;
    let best = null;
    for (const b of blocks()) {
      const r = b.getBoundingClientRect();
      if (r.bottom <= ANCHOR) { best = b; continue; }
      const start = +b.dataset.line, span = +b.dataset.lines || 1;
      if (r.top <= ANCHOR) return start + Math.min(0.999, (ANCHOR - r.top) / Math.max(1, r.height)) * span;
      // in the gap above this block: say we're at its start
      return best ? start : start;
    }
    return best ? +best.dataset.line + (+best.dataset.lines || 1) : 0;
  }
  function scrollToLine(line) {
    let target = null;
    for (const b of blocks()) { if (+b.dataset.line <= line) target = b; else break; }
    if (!target) { window.scrollTo(0, 0); return; }
    const start = +target.dataset.line, span = +target.dataset.lines || 1;
    const r = target.getBoundingClientRect();
    const frac = Math.min(1, Math.max(0, (line - start) / span));
    window.scrollTo(0, Math.max(0, r.top + window.scrollY + frac * r.height - ANCHOR));
  }
  let restoring = 0, reportQueued = false, anchorLine = 0;
  function reportTop() {
    if (restoring || reportQueued) return;
    reportQueued = true;
    setTimeout(() => { reportQueued = false; if (!restoring) { anchorLine = topLine(); post({ type: 'top', line: anchorLine }); } }, 60);  // not rAF: throttled in occluded windows
  }
  window.addEventListener('scroll', reportTop, { passive: true });
  // Hold a restored position while late layout lands (fonts, Mermaid), unless the reader scrolls.
  // A resize (split, sidebar, window) reflows the page; hold the reading position by source line.
  window.addEventListener('resize', () => { layoutSidenotes(); if (anchorLine > 0) restoreLine(anchorLine); });
  function restoreLine(line) {
    anchorLine = line;
    const token = ++restoring;
    let userMoved = false;
    const stop = () => { userMoved = true; };
    window.addEventListener('wheel', stop, { once: true, passive: true });
    window.addEventListener('keydown', stop, { once: true });
    const apply = () => { if (!userMoved && restoring === token) scrollToLine(line); };
    apply();
    setTimeout(apply, 16);
    if (document.fonts) document.fonts.ready.then(apply);
    setTimeout(apply, 150);
    setTimeout(() => { apply(); if (restoring === token) { restoring = 0; reportTop(); } }, 450);
  }

  function props(list) {
    if (!list || !list.length) return '';
    const rows = list.map(p => `<tr><td>${esc(p.key)}</td><td>${p.html || esc(p.value)}</td></tr>`).join('');
    return `<div class="properties"><span class="toggle"></span><div class="rows"><table>${rows}</table></div></div>`;
  }

  // Backlinks at the end of the note (Obsidian's "backlinks in document"); open state is remembered.
  const blOpen = (k, d) => { const v = localStorage.getItem('onyx.bl.' + k); return v === null ? d : v === '1'; };
  function backlinksHTML(list) {
    const items = list.map(b => `<li><a class="internal-link bl-source" data-path="${esc(b.path)}">${esc(b.name)}</a>` +
      (b.folder ? `<span class="bl-folder">${esc(b.folder)}</span>` : '') +
      b.lines.filter(l => /[\p{L}\p{N}]/u.test(l.text)).map(l => `<a class="internal-link bl-context" data-path="${esc(b.path)}" data-line="${l.line}">${esc(l.text)}</a>`).join('') + '</li>').join('');
    return `<section class="doc-backlinks">` +
      `<details data-k="linked"${blOpen('linked', true) ? ' open' : ''}><summary>Linked mentions <span class="bl-count">${list.length}</span></summary>` +
      (list.length ? `<ul>${items}</ul>` : `<p class="bl-empty">Nothing links here yet.</p>`) + `</details>` +
      `<details data-k="unlinked"${blOpen('unlinked', false) ? ' open' : ''}><summary>Unlinked mentions</summary><ul class="bl-unlinked"><li class="bl-empty">…</li></ul></details></section>`;
  }
  document.addEventListener('toggle', e => {
    const d = e.target;
    if (!(d instanceof HTMLDetailsElement) || !d.dataset.k) return;
    localStorage.setItem('onyx.bl.' + d.dataset.k, d.open ? '1' : '0');
    if (d.dataset.k === 'unlinked' && d.open) post({ type: 'unlinked' });
  }, true);

  // Kanban (obsidian-kanban format): drag cards between lanes or within one, check them off,
  // double-click to edit, add, archive. Swift splices the file, so nothing else in it moves.
  function kanbanHTML(lanes) {
    const editable = !P.preview && P.kanbanEditable;
    return `<div class="kanban${editable ? ' editable' : ''}">` + lanes.map((l, li) => l.collapsed ?
      // collapsed: a thin strip, title rotated, with the count; click to expand
      `<section class="lane collapsed" data-lane="${li}"${editable ? ' title="Expand"' : ''}><span class="kb-strip-count">${l.cards.length}</span><span class="kb-strip-title">${parseInlineMath(l.title)}</span></section>` :
      `<section class="lane" data-lane="${li}"><h3>${editable ? '<button class="kb-fold" title="Collapse (right-click: collapse all except this)">&#x2039;</button>' : ''}${parseInlineMath(l.title)}<span class="count">${l.cards.length}</span></h3><div class="kb-cards">` +
      l.cards.map((c, ci) => `<div class="card${c.done ? ' done' : ''}"${editable ? ' draggable="true"' : ''} data-lane="${li}" data-card="${ci}" data-raw="${esc(c.text)}">` +
        (editable ? `<input type="checkbox" class="kb-check"${c.done ? ' checked' : ''} title="Done">` : '') +
        `<div class="kb-text">${parseInlineMath(c.text.replace(/\n/g, ' '))}</div>` +
        (editable ? '<button class="kb-archive" title="Archive card">&#x2193;</button>' : '') + '</div>').join('') +
      `</div>${editable ? '<button class="kb-add">+ Add a card</button>' : ''}</section>`).join('') + '</div>';
  }
  const kb = (m) => post(Object.assign({ type: 'kanban' }, m));
  function kbEditor(host, value, commit) {
    const ta = document.createElement('textarea');
    ta.className = 'kb-edit'; ta.value = value; ta.rows = Math.max(2, value.split('\n').length);
    host.replaceChildren(ta); ta.focus(); ta.select();
    let done = false;
    const finish = (save) => { if (done) return; done = true; save ? commit(ta.value) : Onyx.render(P); };
    ta.addEventListener('keydown', e => {
      if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); finish(true); }
      else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); finish(false); }
    });
    ta.addEventListener('blur', () => finish(true));
    return ta;
  }
  document.addEventListener('click', e => {
    const board = e.target.closest('.kanban.editable');
    if (!board) return;
    const card = e.target.closest('.card');
    const lane = e.target.closest('.lane');
    hideKbMenu();
    if (e.target.closest('.kb-menu button')) return;
    if (lane && lane.classList.contains('collapsed') && !e.target.closest('a')) { kb({ op: 'collapse', lane: +lane.dataset.lane, on: false }); e.stopPropagation(); return; }
    if (e.target.classList.contains('kb-fold') && lane) { kb({ op: 'collapse', lane: +lane.dataset.lane, on: true }); e.stopPropagation(); return; }
    if (e.target.classList.contains('kb-check') && card) { e.preventDefault(); kb({ op: 'toggle', lane: +card.dataset.lane, card: +card.dataset.card }); e.stopPropagation(); }
    else if (e.target.classList.contains('kb-archive') && card) { kb({ op: 'archive', lane: +card.dataset.lane, card: +card.dataset.card }); e.stopPropagation(); }
    else if (e.target.classList.contains('kb-add')) {
      const lane = e.target.closest('.lane'), host = document.createElement('div');
      host.className = 'card adding'; lane.querySelector('.kb-cards').appendChild(host); e.target.style.display = 'none';
      kbEditor(host, '', v => v.trim() ? kb({ op: 'add', lane: +lane.dataset.lane, text: v }) : Onyx.render(P));
      e.stopPropagation();
    }
  }, true);
  // column menu (right-click a lane header or a collapsed strip)
  function hideKbMenu() { document.querySelectorAll('.kb-menu').forEach(m => m.remove()); }
  document.addEventListener('contextmenu', e => {
    const lane = e.target.closest('.kanban.editable .lane');
    if (!lane || !(e.target.closest('h3') || lane.classList.contains('collapsed'))) return;
    e.preventDefault(); hideKbMenu();
    const li = +lane.dataset.lane, m = document.createElement('div');
    m.className = 'kb-menu';
    const folded = lane.classList.contains('collapsed');
    [[folded ? 'Expand' : 'Collapse', { op: 'collapse', lane: li, on: !folded }],
     ['Collapse all except this', { op: 'collapseOthers', lane: li }],
     ['Expand all', { op: 'expandAll' }]].forEach(([t, op]) => {
      const b = document.createElement('button'); b.textContent = t;
      b.addEventListener('click', ev => { ev.stopPropagation(); hideKbMenu(); kb(op); });
      m.appendChild(b);
    });
    m.style.left = (e.pageX) + 'px'; m.style.top = (e.pageY) + 'px';
    document.body.appendChild(m);
  });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') hideKbMenu(); });
  document.addEventListener('dblclick', e => {
    const card = e.target.closest('.kanban.editable .card');
    if (!card || e.target.closest('a') || e.target.classList.contains('kb-check')) return;
    e.preventDefault();
    card.draggable = false;
    kbEditor(card.querySelector('.kb-text'), card.dataset.raw, v => {
      if (!v.trim() || v === card.dataset.raw) return Onyx.render(P);
      kb({ op: 'edit', lane: +card.dataset.lane, card: +card.dataset.card, text: v });
    });
  });
  let DRAG = null;
  function kbDropIndex(lane, y) {
    const cards = [...lane.querySelectorAll('.kb-cards > .card:not(.dragging):not(.adding)')];
    const i = cards.findIndex(c => { const r = c.getBoundingClientRect(); return y < r.top + r.height / 2; });
    return { cards, index: i < 0 ? cards.length : i };
  }
  document.addEventListener('dragstart', e => {
    const card = e.target.closest && e.target.closest('.kanban.editable .card');
    if (!card) return;
    DRAG = { lane: +card.dataset.lane, card: +card.dataset.card, el: card };
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', card.dataset.raw);
    requestAnimationFrame(() => card.classList.add('dragging'));
  });
  document.addEventListener('dragover', e => {
    const lane = DRAG && e.target.closest && e.target.closest('.kanban.editable .lane');
    if (!lane) return;
    e.preventDefault(); e.dataTransfer.dropEffect = 'move';
    if (lane.classList.contains('collapsed')) { lane.classList.add('kb-over'); return; }
    const { cards, index } = kbDropIndex(lane, e.clientY);
    let mark = document.querySelector('.kb-drop');
    if (!mark) { mark = document.createElement('div'); mark.className = 'kb-drop'; }
    const list = lane.querySelector('.kb-cards');
    if (index < cards.length) list.insertBefore(mark, cards[index]); else list.appendChild(mark);
  });
  document.addEventListener('drop', e => {
    const lane = DRAG && e.target.closest && e.target.closest('.kanban.editable .lane');
    if (!lane) return;
    e.preventDefault();
    const index = lane.classList.contains('collapsed') ? +lane.querySelector('.kb-strip-count').textContent : kbDropIndex(lane, e.clientY).index;
    const to = +lane.dataset.lane, d = DRAG;
    DRAG = null;
    document.querySelectorAll('.kb-drop').forEach(m => m.remove());
    if (!(to === d.lane && index === d.card)) kb({ op: 'move', lane: d.lane, card: d.card, toLane: to, index });
    else d.el.classList.remove('dragging');
  });
  document.addEventListener('dragend', () => {
    if (DRAG) DRAG.el.classList.remove('dragging');
    DRAG = null;
    document.querySelectorAll('.kb-drop').forEach(m => m.remove());
    document.querySelectorAll('.kb-over').forEach(m => m.classList.remove('kb-over'));
  });
  document.addEventListener('dragleave', e => { const l = e.target.closest && e.target.closest('.lane.collapsed'); if (l && !l.contains(e.relatedTarget)) l.classList.remove('kb-over'); });

  function sidenotes() {
    let i = 0;
    page.querySelectorAll('a[data-footnote-ref]').forEach((ref) => {
      if (ref.closest('.sidenote')) return;
      const href = ref.getAttribute('href') || '';
      const id = decodeURIComponent((href.split('#')[1] || href.replace(/^#/, '')));
      const li = id && document.getElementById(id);
      if (!li) return;
      const clone = li.cloneNode(true);
      clone.querySelectorAll('[data-footnote-backref]').forEach(b => b.remove());
      const s = document.createElement('aside');
      s.className = 'sidenote';
      s.id = 'sn-' + (++i);
      ref.dataset.sn = s.id;
      const sup = ref.closest('sup') || ref;
      // `[^x]: {-} text` is an unnumbered margin note (Tufte's \marginnote): no number in
      // the text or the margin; at narrow widths a small ⊕ opens it.
      const mark = unmark(clone);
      if (mark) { s.classList.add('marginnote'); sup.classList.add('mn-ref'); ref.textContent = '\u2295'; }
      s.innerHTML = (mark ? '' : `<span class="num">${ref.textContent}</span>`) + clone.innerHTML;
      // A float can't leave a scrolling box (a wide table): set the note just before it.
      const host = sup.closest('.table-wrap, .kanban, pre, .mermaid, .onyx-dataview');
      if (host) host.before(s); else sup.after(s);
    });
    // Margin notes don't take a number; keep the numbered ones 1, 2, 3…
    if (page.querySelector('.marginnote')) {
      let n = 0;
      page.querySelectorAll('a[data-footnote-ref][data-sn]').forEach(ref => {
        if ((ref.closest('sup') || ref).classList.contains('mn-ref')) return;
        ref.textContent = ++n;
        const num = document.getElementById(ref.dataset.sn)?.querySelector('.num');
        if (num) num.textContent = n;
      });
    }
    layoutSidenotes();
  }
  // Strip a leading "{-}" from a note's first text; true if it was there.
  function unmark(root) {
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    while (w.nextNode()) {
      const t = w.currentNode;
      if (!t.nodeValue.trim()) continue;
      if (!/^\s*\{-\}\s*/.test(t.nodeValue)) return false;
      t.nodeValue = t.nodeValue.replace(/^\s*\{-\}\s*/, '');
      return true;
    }
    return false;
  }

  // Pack margin notes so none overlaps the one above: each note sits as close to its
  // reference as it can, nudged down just enough to clear the previous note plus a gap.
  // Late layout (fonts, images, Mermaid, details, a resize) re-runs it; see scheduleNotes.
  const NOTE_GAP = 8;
  const inMargin = () => window.innerWidth >= 1120 || document.body.classList.contains('print');
  function layoutSidenotes() {
    const notes = [...page.querySelectorAll('.sidenote')];
    notes.forEach(s => { s.style.marginTop = ''; });
    if (!inMargin()) return;
    let lastBottom = -Infinity;
    for (const s of notes) {
      if (!s.getClientRects().length) continue;   // hidden (a closed <details>)
      const rect = s.getBoundingClientRect();
      const overlap = lastBottom + NOTE_GAP - rect.top;
      if (overlap > 0) s.style.marginTop = overlap + 'px';
      lastBottom = s.getBoundingClientRect().bottom;
    }
  }
  let notesQueued = false;
  function scheduleNotes() {
    if (notesQueued || !page.querySelector('.sidenote')) return;
    notesQueued = true;
    setTimeout(() => { notesQueued = false; layoutSidenotes(); }, 0);   // not rAF: throttled in occluded windows
  }
  page.addEventListener('load', scheduleNotes, true);            // images, video posters
  document.addEventListener('toggle', scheduleNotes, true);      // <details> callouts and backlinks
  if (document.fonts) document.fonts.addEventListener('loadingdone', scheduleNotes);
  if (window.ResizeObserver) {
    let w = 0;
    new ResizeObserver(es => { const nw = Math.round(es[0].contentRect.width); if (nw !== w) { w = nw; scheduleNotes(); } }).observe(page);
  }

  async function mermaids() {
    const nodes = [...page.querySelectorAll('pre.mermaid')];
    if (!nodes.length || !window.mermaid) return;
    const cs = getComputedStyle(document.body);
    const bg = cs.getPropertyValue('--background-primary').trim(), ink = cs.getPropertyValue('--text-normal').trim();
    mermaid.initialize({
      startOnLoad: false, theme: 'base', securityLevel: 'strict',
      fontFamily: 'Latin Modern Roman, Georgia, serif',
      htmlLabels: false, markdownAutoWrap: false, flowchart: { curve: 'linear', htmlLabels: false, padding: 12, wrappingWidth: 600 },
      themeVariables: { background: bg, primaryColor: bg, primaryTextColor: ink, primaryBorderColor: ink, lineColor: ink,
        secondaryColor: bg, tertiaryColor: bg, mainBkg: bg, nodeBorder: ink, clusterBkg: bg, clusterBorder: ink, edgeLabelBackground: bg,
        fontFamily: 'Latin Modern Roman, Georgia, serif', fontSize: '15px' }
    });
    try { await document.fonts.load('15px "Latin Modern Roman"'); await document.fonts.ready; } catch (e) { }
    try { await mermaid.run({ nodes, suppressErrors: true }); } catch (e) { }
    scheduleNotes();
  }

  function decorate() {
    let task = 0;
    page.querySelectorAll('input[type=checkbox]').forEach(cb => {
      if (cb.closest('.markdown-embed') || cb.closest('.kanban') || cb.closest('.onyx-dataview')) return;
      cb.removeAttribute('disabled');
      cb.dataset.task = task++;
      const li = cb.closest('li');
      if (li) { li.classList.add('task-list-item'); if (cb.checked) li.classList.add('is-checked'); }
    });
    page.querySelectorAll('.onyx-inline-md').forEach(s => { s.innerHTML = parseInlineMath(s.textContent); });
  }

  // ⌘F in the reader: mark every match in the note (not the backlinks), the current one brighter.
  let FIND = null;
  function clearFind() {
    page.querySelectorAll('mark.onyx-find').forEach(m => { const p = m.parentNode; p.replaceChild(document.createTextNode(m.textContent), m); p.normalize(); });
  }
  function applyFind(reveal) {
    clearFind();
    if (!FIND || !FIND.q) return { count: 0, index: 0 };
    const fold = (x) => x.replace(/[\u2018\u2019]/g, "'").replace(/[\u201c\u201d]/g, '"').replace(/[\u2013\u2014]/g, '-').replace(/\u00a0/g, ' ');
    const q = fold(FIND.cs ? FIND.q : FIND.q.toLowerCase());
    const walker = document.createTreeWalker(page, NodeFilter.SHOW_TEXT, { acceptNode(n) {
      const e = n.parentElement;
      return !e || e.closest('script, style, svg, .doc-backlinks, .properties .toggle') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
    } });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    const marks = [];
    for (const n of nodes) {
      const t = fold(FIND.cs ? n.data : n.data.toLowerCase());
      let i = t.indexOf(q), node = n, off = 0;
      while (i >= 0) {
        const hit = node.splitText(i - off);
        const rest = hit.splitText(q.length);
        const m = document.createElement('mark');
        m.className = 'onyx-find';
        hit.parentNode.replaceChild(m, hit);
        m.appendChild(hit);
        marks.push(m);
        node = rest; off = i + q.length;
        i = t.indexOf(q, off);
      }
    }
    if (!marks.length) return { count: 0, index: 0 };
    FIND.i = ((FIND.i % marks.length) + marks.length) % marks.length;
    const cur = marks[FIND.i];
    cur.classList.add('current');
    if (reveal) {
      revealFolded(cur);
      const d = cur.closest('details'); if (d && !d.open) d.open = true;
      cur.scrollIntoView({ block: 'center' });
    }
    return { count: marks.length, index: FIND.i };
  }

  // Typeset reading (Settings ▸ Typography): body classes the typeset.css rules key off.
  function typesetClasses(t) {
    if (!t) return '';
    const print = t.print ? ' print' : '';
    if (!t.on) return print;
    return ' typeset' + (t.onum !== false ? ' onum' : '') + (t.hyphens !== false ? ' hyph' : '') + (t.justify ? ' just' : '') + (t.face === 'et' ? ' face-et' : '') + print;
  }

  // Heading folds (Settings ▸ Editor ▸ Fold headings). Display only: the markdown is never
  // touched. Swift keeps the folded source lines per note, shared with the editor.
  let FOLDS = new Set();
  const HEAD = /^H[1-6]$/;
  function foldHeads() { return [...page.children].filter(e => HEAD.test(e.tagName) && e.dataset.line && !e.classList.contains('fallback-title')); }
  function sectionOf(h) {   // following blocks up to the next heading of the same or a higher level
    const lvl = +h.tagName[1], out = [];
    for (let e = h.nextElementSibling; e; e = e.nextElementSibling) {
      if (HEAD.test(e.tagName) && +e.tagName[1] <= lvl) break;
      if (e.classList.contains('doc-backlinks') || e.classList.contains('footnotes')) break;
      out.push(e);
    }
    return out;
  }
  function setupFolds() {
    FOLDS = new Set(((P && P.folds) || []).map(Number));
    if (!P || !P.foldable || P.preview || P.kanban) return;
    for (const h of foldHeads()) {
      if (!sectionOf(h).some(e => e.textContent.trim() || e.querySelector('img, svg, video, iframe, table, hr, canvas'))) continue;
      h.classList.add('foldable');
      const t = document.createElement('span'); t.className = 'fold-toggle'; t.setAttribute('role', 'button'); t.setAttribute('aria-label', 'Fold section'); h.prepend(t);
      const m = document.createElement('span'); m.className = 'fold-more'; m.setAttribute('role', 'button'); m.setAttribute('aria-label', 'Unfold section'); h.append(m);
    }
    refreshFolds(false);
  }
  function refreshFolds(relayout = true) {
    const heads = foldHeads();
    for (const h of heads) h.classList.toggle('folded', h.classList.contains('foldable') && FOLDS.has(+h.dataset.line));
    // Nested folds survive opening their parent: hidden = covered by any folded section.
    const hidden = new Set();
    for (const h of heads) if (h.classList.contains('folded')) for (const e of sectionOf(h)) hidden.add(e);
    for (const e of page.children) e.classList.toggle('fold-hidden', hidden.has(e));
    if (relayout && P && P.sidenotes) layoutSidenotes();
  }
  function postFolds() { post({ type: 'folds', lines: [...FOLDS] }); }
  function revealFolded(el) {   // Find and heading jumps open the folds they land in
    const top = el && [...page.children].find(c => c === el || c.contains(el));
    if (!top || !top.classList.contains('fold-hidden')) return;
    for (const h of foldHeads()) if (h.classList.contains('folded') && sectionOf(h).includes(top)) FOLDS.delete(+h.dataset.line);
    refreshFolds(); postFolds();
  }
  document.addEventListener('click', e => {
    const t = e.target.closest && e.target.closest('.fold-toggle, .fold-more');
    if (!t) return;
    e.preventDefault(); e.stopPropagation();
    const h = t.parentElement, l = +h.dataset.line;
    FOLDS.has(l) ? FOLDS.delete(l) : FOLDS.add(l);
    refreshFolds(); postFolds();
  }, true);

  // Drag to resize an embedded image (focused pane only). Each sizable <img> is numbered among the
  // embeds of the same target in its source block, so Swift rewrites exactly that occurrence.
  function markEmbeds() {
    if (!P.editable) return;
    const seen = new Map();
    for (const img of page.querySelectorAll('img[data-embed]')) {
      if (img.closest('.markdown-embed, .kanban, .onyx-dataview, .sidenote, .footnotes, .backlinks, .onyx-dv-inline')) continue;
      const b = img.closest('[data-line]');
      if (!b) continue;
      const t = img.dataset.embedTarget || '';
      const key = b.dataset.line + '\u0000' + img.dataset.embed + '\u0000' + (img.dataset.embed === 'wiki' ? t.trim().toLowerCase() : t);
      const n = seen.get(key) || 0;
      seen.set(key, n + 1);
      img.dataset.occ = n;
      img.classList.add('resizable');
    }
  }
  const grip = document.createElement('div');
  grip.id = 'img-grip';
  grip.title = 'Drag to resize · double-click for natural size';
  grip.innerHTML = '<span class="ig-size"></span>';
  let gripImg = null, drag = null;
  function placeGrip(img) {
    if (!grip.isConnected) document.body.appendChild(grip);
    const r = img.getBoundingClientRect();
    grip.style.left = (r.right + window.scrollX - 18) + 'px';
    grip.style.top = (r.bottom + window.scrollY - 18) + 'px';
  }
  function hideGrip(force) {
    if (drag && !force) return;
    drag = null; gripImg = null;
    grip.classList.remove('shown', 'dragging');
    document.body.classList.remove('img-resizing');
  }
  function commitSize(img, width) {
    const b = img.closest('[data-line]');
    if (!b) return;
    post({ type: 'imageSize', line: +b.dataset.line, lines: +b.dataset.lines || 1, kind: img.dataset.embed, target: img.dataset.embedTarget || '', occurrence: +img.dataset.occ, width });
  }
  document.addEventListener('mouseover', e => {
    if (drag) return;
    const img = e.target.closest && e.target.closest('img.resizable');
    if (img && img.naturalWidth) { gripImg = img; placeGrip(img); grip.classList.add('shown'); }
    else if (!grip.contains(e.target)) hideGrip();
  });
  grip.addEventListener('mousedown', e => {
    if (!gripImg || e.button !== 0) return;
    e.preventDefault(); e.stopPropagation();
    const img = gripImg, r = img.getBoundingClientRect();
    const box = img.parentElement || page;
    // A block image is centered, so its corner moves half as far as its width grows.
    drag = { img, x: e.clientX, w: r.width, centered: getComputedStyle(img).display === 'block', max: Math.max(32, box.clientWidth || page.clientWidth), moved: false, width: Math.round(r.width) };
    grip.firstChild.textContent = '';
    grip.classList.add('dragging');
    document.body.classList.add('img-resizing');
  });
  document.addEventListener('mousemove', e => {
    if (!drag) return;
    const dx = (e.clientX - drag.x) * (drag.centered ? 2 : 1);
    if (!drag.moved && Math.abs(dx) < 3) return;
    drag.moved = true;
    const w = Math.round(Math.max(32, Math.min(drag.max, drag.w + dx)));
    drag.width = w;
    drag.img.removeAttribute('height');
    drag.img.style.width = w + 'px'; drag.img.style.height = 'auto';
    grip.firstChild.textContent = w + ' px';
    placeGrip(drag.img);
  });
  document.addEventListener('mouseup', () => {
    if (!drag) return;
    const d = drag;
    drag = null;
    grip.classList.remove('dragging');
    document.body.classList.remove('img-resizing');
    if (d.moved) commitSize(d.img, d.width);
  });
  grip.addEventListener('click', e => { e.preventDefault(); e.stopPropagation(); });   // never the image viewer
  grip.addEventListener('dblclick', e => {
    e.preventDefault(); e.stopPropagation();
    const img = gripImg;
    if (!img) return;
    img.removeAttribute('width'); img.removeAttribute('height'); img.style.width = ''; img.style.height = '';
    commitSize(img, null);
    hideGrip(true);
  });

  window.Onyx = {
    render(payload) {
      P = payload;
      hideGrip(true);
      document.body.className = (payload.dark ? 'theme-dark' : 'theme-light') + (payload.sidenotes ? ' sidenotes' : '') + (payload.preview ? ' preview' : '') + typesetClasses(payload.typeset);
      document.documentElement.classList.toggle('dark', !!payload.dark);
      const y = window.scrollY;
      const md = stripComments(payload.markdown);
      let html;
      if (payload.kanban) {
        html = `<h1>${esc(payload.name)}</h1>` + kanbanHTML(payload.kanban);
      } else {
        try { html = parseWithLines(md, payload.lineBase || 0); }
        catch (e) { try { html = withMath(md, s => mainMarked.parse(s)); } catch (e2) { html = `<pre>${esc(md)}</pre>`; } }
        html = html.replace(/<div class="onyx-dataview" data-i="(\d+)"><\/div>/g, (_, i) => payload.dataview[+i] || '');
        html = html.replace(/<span class="onyx-dv-inline" data-i="(\d+)"><\/span>/g, (_, i) => payload.dvinline?.[+i] || '');
        if (!/<h1[\s>]/.test(html)) html = `<h1 class="fallback-title">${esc(payload.name)}</h1>` + html;
      }
      page.classList.add('instant');
      if (!payload.keepScroll) page.classList.remove('shown');
      const kbx = (page.querySelector('.kanban') || {}).scrollLeft || 0;
      page.innerHTML = props(payload.props) + html + (payload.kanban || payload.preview ? '' : backlinksHTML(payload.backlinks || []));
      if (payload.preview) {   // the card header already names the note
        const h = page.querySelector('h1');
        if (h && h.textContent.trim().toLowerCase() === String(payload.name).toLowerCase()) h.remove();
      }
      markLines();
      markEmbeds();
      decorate();
      if (payload.sidenotes) sidenotes();
      page.querySelectorAll('.footnotes li').forEach(unmark);   // a margin note at the end is just a note
      if (window.OnyxTypeset) OnyxTypeset.apply(page, Object.assign({ props: payload.props }, payload.typeset || {}));
      if (payload.sidenotes) { layoutSidenotes(); if (document.fonts) document.fonts.ready.then(scheduleNotes); }
      document.body.classList.toggle('has-notes', !!page.querySelector('.sidenote'));
      mermaids();
      setupFolds();
      if (kbx && page.querySelector('.kanban')) page.querySelector('.kanban').scrollLeft = kbx;
      if (FIND) post(Object.assign({ type: 'findCount' }, applyFind(false)));
      const ud = page.querySelector('details[data-k=unlinked]');
      if (ud && ud.open) post({ type: 'unlinked' });
      if (payload.keepScroll) { window.scrollTo(0, y); page.classList.add('shown'); requestAnimationFrame(() => page.classList.remove('instant')); }
      else if (payload.line > 0) {
        // Opened at a remembered spot (⌘↩ from the editor, or a split): no slide-in, just land there.
        page.classList.add('shown');
        restoreLine(payload.line);
        requestAnimationFrame(() => page.classList.remove('instant'));
      } else {
        window.scrollTo(0, 0);
        requestAnimationFrame(() => { page.classList.remove('instant'); requestAnimationFrame(() => page.classList.add('shown')); });
      }
    },
    setType(size, measure) {
      document.documentElement.style.setProperty('--font-text-size', size + 'px');
      document.documentElement.style.setProperty('--file-line-width', measure + 'rem');
    },
    scrollToLine(line) { restoreLine(line); },
    // Export as PDF / Print: Swift sizes the page (CSS px), then waits for printReady().
    setPrint(g) {
      // Everything in points, so the screen layout (where sidenotes are packed) and the
      // printed page are the same layout; @page carries the paper and its margins.
      const r = document.documentElement.style;
      for (const k of ['text', 'note', 'gap']) if (g[k]) r.setProperty('--print-' + k, g[k] + 'pt');
      if (g.size) r.setProperty('--font-text-size', g.size + 'pt');
      let st = document.getElementById('onyx-page');
      if (!st) { st = document.createElement('style'); st.id = 'onyx-page'; document.head.appendChild(st); }
      // A long listing may run across pages (TeX would break it too); short ones stay whole.
      page.querySelectorAll('pre, .table-wrap').forEach(b => { if (b.textContent.split('\n').length > 14) b.classList.add('may-break'); });
      if (g.paper) st.textContent = `@page { size: ${g.paper[0]}pt ${g.paper[1]}pt; margin: ${g.margin.map(m => m + 'pt').join(' ')}; }`;
      layoutSidenotes();
    },
    printReady() {
      const imgs = [...page.querySelectorAll('img')].every(i => i.complete);
      const mer = !page.querySelector('pre.mermaid:not([data-processed])') || !window.mermaid;
      const ok = (!document.fonts || document.fonts.status === 'loaded') && imgs && mer;
      if (ok) layoutSidenotes();
      return ok;
    },
    find(q, cs, i, reveal) { FIND = { q, cs, i }; return applyFind(reveal); },
    findClear() { FIND = null; clearFind(); },
    setUnlinked(list) {
      const ul = page.querySelector('.bl-unlinked');
      if (!ul) return;
      ul.innerHTML = list.length ? list.map(b => `<li><a class="internal-link bl-source" data-path="${esc(b.path)}">${esc(b.name)}</a><span class="bl-context">${esc(b.text)}</span></li>`).join('')
        : '<li class="bl-empty">No unlinked mentions.</li>';
      const s = page.querySelector('details[data-k=unlinked] summary');
      if (s) s.innerHTML = `Unlinked mentions <span class="bl-count">${list.length}</span>`;
    },
    // Canvas cards: markdown → HTML against the card's own links/embeds (no line anchors).
    fragment(md, ctx) {
      const old = P;
      P = Object.assign({ links: {}, embeds: {}, base: '' }, ctx || {});
      try { return withMath(stripComments(md || ''), s => embedMarked.parse(s)); }
      catch (e) { return `<pre>${esc(md)}</pre>`; }
      finally { P = old; }
    },
    // test hook (Tests/reader): the HTML for a note body, line markers included, no DOM work
    _html(md) { return parseWithLines(stripComments(md), 0); },
    setFolds(lines) { FOLDS = new Set(lines.map(Number)); refreshFolds(); },
    foldCommand(id) {
      const heads = foldHeads().filter(h => h.classList.contains('foldable'));
      if (!heads.length) return;
      if (id === 'foldall') heads.forEach(h => FOLDS.add(+h.dataset.line));
      else if (id === 'unfoldall') FOLDS.clear();
      else {
        // the section being read: the last visible heading at or above the reading line
        let cur = null;
        for (const h of heads) { if (h.classList.contains('fold-hidden')) continue; if (h.getBoundingClientRect().top <= ANCHOR + 4) cur = h; else break; }
        cur = cur || heads.find(h => !h.classList.contains('fold-hidden'));
        if (!cur) return;
        const l = +cur.dataset.line, on = id === 'fold' ? true : id === 'unfold' ? false : !FOLDS.has(l);
        on ? FOLDS.add(l) : FOLDS.delete(l);
        refreshFolds(); postFolds();
        if (on && cur.getBoundingClientRect().top < 0) cur.scrollIntoView({ block: 'start' });
        return;
      }
      refreshFolds(); postFolds();
    },
    scrollToHeading(i) {
      const hs = [...page.querySelectorAll('h1,h2,h3,h4,h5,h6')].filter(h => !h.closest('.markdown-embed') && !h.classList.contains('fallback-title') && !h.closest('.footnotes') && !h.closest('.kanban'));
      const h = hs[i];
      if (h) revealFolded(h);
      if (h) h.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
    },
  };

  // The native graph card is shared with inspector links. Swift owns the 400 ms delay.
  document.addEventListener('mouseover', e => {
    const a = e.target.closest('a.internal-link[data-path]');
    if (!a || !a.dataset.path || a.contains(e.relatedTarget) || (P && P.preview)) return;
    const r = a.getBoundingClientRect();
    post({ type: 'preview', path: a.dataset.path, heading: a.dataset.heading || '', x: r.x, y: r.y, width: r.width, height: r.height });
  });
  document.addEventListener('mouseout', e => {
    const a = e.target.closest('a.internal-link');
    if (a && !a.contains(e.relatedTarget)) post({ type: 'previewEnd' });
  });
  document.addEventListener('click', (e) => {
    post({ type: 'previewEnd' });
    const dv = e.target.closest('input[type=checkbox][data-dv-task]');
    if (dv) { e.preventDefault(); post({ type: 'dvtask', path: dv.dataset.path || '', index: +dv.dataset.index }); return; }
    const cb = e.target.closest('input[type=checkbox][data-task]');
    if (cb) { e.preventDefault(); post({ type: 'task', index: +cb.dataset.task }); return; }
    const play = e.target.closest('.ae-play');
    if (play) { const au = play.parentElement.querySelector('audio'); if (au) { if (au.paused) { document.querySelectorAll('.audio-embed audio').forEach(o => { if (o !== au) o.pause(); }); au.play(); } else au.pause(); } return; }
    const track = e.target.closest('.ae-track');
    if (track) { const au = track.parentElement.querySelector('audio'); const r = track.getBoundingClientRect(); if (au && isFinite(au.duration)) { au.currentTime = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * au.duration; aeSync(au); } return; }
    const a = e.target.closest('a');
    const img = !a && e.target.closest('img[data-path]');
    if (img && img.dataset.path) { post({ type: 'open', path: img.dataset.path, target: img.dataset.path }); return; }   // an image opens in the viewer
    if (!a) return;
    if (a.classList.contains('tag')) { e.preventDefault(); post({ type: 'tag', tag: a.dataset.tag }); return; }
    if (a.classList.contains('internal-link')) {
      e.preventDefault();
      const m = { type: 'open', path: a.dataset.path || '', target: a.dataset.target || '', heading: a.dataset.heading || null };
      if (a.dataset.line) m.line = +a.dataset.line;
      post(m);
      return;
    }
    const href = a.getAttribute('href') || '';
    if (a.hasAttribute('data-footnote-ref')) {
      e.preventDefault();
      const note = (a.dataset.sn && document.getElementById(a.dataset.sn)) || (a.closest('sup') || a).nextElementSibling;
      if (note && note.classList.contains('sidenote') && window.innerWidth < 1120) {
        const open = note.classList.toggle('is-open');
        page.querySelectorAll('.sidenote.is-open').forEach(s => { if (s !== note) s.classList.remove('is-open'); });
        if (open) note.classList.add('is-open');
      }
      return;
    }
    if (href.startsWith('#')) return; // in-note jumps
    if (/^(https?|mailto|obsidian):/i.test(href)) { e.preventDefault(); post({ type: 'url', url: href }); }
  });
})();


// Floating scrollbar: a 3px thumb drawn over the page (WebKit's own is hidden so it reserves no
// gutter). It fades in while scrolling or with the pointer near the edge, out after ~0.9s idle,
// and can be dragged.
(function () {
  const root = document.documentElement;
  const bar = document.createElement('div'); bar.id = 'onyx-sb';
  const thumb = document.createElement('i'); bar.appendChild(thumb);
  const mount = () => { if (!bar.isConnected) document.body.appendChild(bar); };
  let idle = 0, hot = false, drag = null;
  const metrics = () => {
    const vh = window.innerHeight, sh = root.scrollHeight;
    const h = Math.max(36, vh * vh / sh), max = sh - vh;
    return { vh, sh, h, max, top: max > 0 ? (vh - h - 4) * (window.scrollY / max) + 2 : 2 };
  };
  const place = () => {
    mount();
    const m = metrics();
    bar.style.height = m.vh + 'px';
    thumb.style.height = m.h + 'px'; thumb.style.top = m.top + 'px';
    return m.max > 1;
  };
  const show = (hold) => {
    if (!place()) { bar.className = ''; return; }
    bar.className = 'on' + (hot || drag ? ' hot' : '');
    clearTimeout(idle);
    if (!hold) idle = setTimeout(() => { if (!hot && !drag) bar.className = 'off'; }, 900);
  };
  window.addEventListener('scroll', () => show(false), { passive: true });
  window.addEventListener('resize', () => { if (bar.className.startsWith('on')) place(); });
  window.addEventListener('mousemove', (e) => {
    const near = e.clientX > window.innerWidth - 14;
    if (near !== hot) { hot = near; show(near); }
  }, { passive: true });
  document.addEventListener('mouseleave', () => { hot = false; show(false); });
  bar.addEventListener('mousedown', (e) => {
    const m = metrics();
    const r = thumb.getBoundingClientRect();
    if (e.clientY < r.top || e.clientY > r.bottom) {      // click in the gutter: jump there
      window.scrollTo(0, (e.clientY - m.h / 2) / (m.vh - m.h) * m.max);
    }
    drag = { y: e.clientY, s: window.scrollY, m: metrics() };
    e.preventDefault();
  });
  window.addEventListener('mousemove', (e) => {
    if (!drag) return;
    const { m } = drag;
    window.scrollTo(0, drag.s + (e.clientY - drag.y) * m.max / Math.max(1, m.vh - m.h - 4));
  });
  window.addEventListener('mouseup', () => { if (drag) { drag = null; show(false); } });
})();
