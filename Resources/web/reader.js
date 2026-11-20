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

  const embedDepth = { n: 0 };
  function embedHTML(inner) {
    const l = parseLink(inner);
    const e = P.embeds[l.target.toLowerCase()];
    if (!e) return linkHTML(inner);
    const width = l.alias && /^\d+(x\d+)?$/.test(l.alias) ? ` width="${l.alias.split('x')[0]}"` : '';
    switch (e.type) {
      case 'image': return `<img src="${e.url}"${width} alt="${esc(l.target)}">`;
      case 'audio': return `<audio controls src="${e.url}"></audio>`;
      case 'video': return `<video controls src="${e.url}"></video>`;
      case 'pdf': return `<embed class="pdf-embed" src="${e.url}" type="application/pdf">`;
      case 'note':
        if (embedDepth.n > 1) return linkHTML(inner);
        embedDepth.n++;
        const html = embedMarked.parse(stripComments(e.markdown));
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
      const src = /^(https?|data|onyx):/i.test(href) ? href : P.base + href.replace(/^\.\//, '');
      return `<img src="${esc(src)}" alt="${esc(text)}"${title ? ` title="${esc(title)}"` : ''}>`;
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

  const mainMarked = new marked.Marked({ gfm: true, breaks: false });
  mainMarked.use({ extensions: [wikilink, highlight, tag], renderer });
  if (window.markedFootnote) mainMarked.use(markedFootnote({ description: 'Notes', refMarkers: false }));
  const embedMarked = new marked.Marked({ gfm: true });
  embedMarked.use({ extensions: [wikilink, highlight, tag], renderer });

  function stripComments(md) { return md.replace(/%%[\s\S]*?%%/g, ''); }

  function props(list) {
    if (!list || !list.length) return '';
    const rows = list.map(p => `<tr><td>${esc(p.key)}</td><td>${esc(p.value)}</td></tr>`).join('');
    return `<div class="properties"><span class="toggle"></span><div class="rows"><table>${rows}</table></div></div>`;
  }

  function kanbanHTML(lanes) {
    return '<div class="kanban">' + lanes.map(l =>
      `<section class="lane"><h3>${embedMarked.parseInline(l.title)}<span class="count">${l.cards.length}</span></h3>` +
      l.cards.map(c => `<div class="card${c.done ? ' done' : ''}">${embedMarked.parseInline(c.text.replace(/\n/g, ' '))}</div>`).join('') +
      '</section>').join('') + '</div>';
  }

  function sidenotes() {
    page.querySelectorAll('a[data-footnote-ref]').forEach((ref, i) => {
      const id = (ref.getAttribute('href') || '').slice(1);
      const li = id && document.getElementById(id);
      if (!li) return;
      const clone = li.cloneNode(true);
      clone.querySelectorAll('[data-footnote-backref]').forEach(b => b.remove());
      const s = document.createElement('span');
      s.className = 'sidenote';
      s.innerHTML = `<span class="num">${ref.textContent}</span>` + clone.innerHTML;
      const sup = ref.closest('sup') || ref;
      sup.after(s);
    });
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
  }

  function decorate() {
    let task = 0;
    page.querySelectorAll('input[type=checkbox]').forEach(cb => {
      if (cb.closest('.markdown-embed') || cb.closest('.kanban')) return;
      cb.removeAttribute('disabled');
      cb.dataset.task = task++;
      const li = cb.closest('li');
      if (li) { li.classList.add('task-list-item'); if (cb.checked) li.classList.add('is-checked'); }
    });
    page.querySelectorAll('.onyx-inline-md').forEach(s => { s.innerHTML = embedMarked.parseInline(s.textContent); });
  }

  window.Onyx = {
    render(payload) {
      P = payload;
      document.body.className = (payload.dark ? 'theme-dark' : 'theme-light') + (payload.sidenotes ? ' sidenotes' : '');
      const y = window.scrollY;
      const md = stripComments(payload.markdown);
      let html;
      if (payload.kanban) {
        html = `<h1>${esc(payload.name)}</h1>` + kanbanHTML(payload.kanban);
      } else {
        try { html = mainMarked.parse(md); } catch (e) { html = `<pre>${esc(md)}</pre>`; }
        html = html.replace(/<div class="onyx-dataview" data-i="(\d+)"><\/div>/g, (_, i) => payload.dataview[+i] || '');
        if (!/<h1[\s>]/.test(html)) html = `<h1 class="fallback-title">${esc(payload.name)}</h1>` + html;
      }
      page.classList.add('instant');
      if (!payload.keepScroll) page.classList.remove('shown');
      page.innerHTML = props(payload.props) + html;
      decorate();
      if (payload.sidenotes) sidenotes();
      document.body.classList.toggle('has-notes', !!page.querySelector('.sidenote'));
      mermaids();
      if (payload.keepScroll) { window.scrollTo(0, y); }
      else {
        window.scrollTo(0, 0);
        requestAnimationFrame(() => { page.classList.remove('instant'); requestAnimationFrame(() => page.classList.add('shown')); });
      }
    },
    setType(size, measure) {
      document.documentElement.style.setProperty('--font-text-size', size + 'px');
      document.documentElement.style.setProperty('--file-line-width', measure + 'rem');
    },
    scrollToHeading(i) {
      const hs = [...page.querySelectorAll('h1,h2,h3,h4,h5,h6')].filter(h => !h.closest('.markdown-embed') && !h.classList.contains('fallback-title') && !h.closest('.footnotes') && !h.closest('.kanban'));
      const h = hs[i];
      if (h) h.scrollIntoView({ behavior: 'smooth', block: 'start' });
    },
  };

  document.addEventListener('click', (e) => {
    const cb = e.target.closest('input[type=checkbox][data-task]');
    if (cb) { e.preventDefault(); post({ type: 'task', index: +cb.dataset.task }); return; }
    const a = e.target.closest('a');
    if (!a) return;
    if (a.classList.contains('tag')) { e.preventDefault(); post({ type: 'tag', tag: a.dataset.tag }); return; }
    if (a.classList.contains('internal-link')) {
      e.preventDefault();
      post({ type: 'open', path: a.dataset.path || '', target: a.dataset.target || '', heading: a.dataset.heading || null });
      return;
    }
    const href = a.getAttribute('href') || '';
    if (href.startsWith('#')) return; // footnote jumps
    if (/^(https?|mailto|obsidian):/i.test(href)) { e.preventDefault(); post({ type: 'url', url: href }); }
  });
})();
