// Onyx typesetting pass: the things TeX does for you, done to the rendered page.
// Smart quotes, dashes and ellipses; ties after short words; true small caps for
// acronyms; a small-caps lead-in (or drop cap) to open the text; epigraphs with
// attributions; figures and table captions; numeric and compact table columns; optical margin
// kerns for quotes. Code, math, tags and interface text are never touched.
// Pure string helpers are exported for Tests/reader; apply() works on the DOM.
(function () {
  const SKIP = 'code, pre, kbd, samp, script, style, textarea, svg, .mermaid, .math, .katex, .tag, .field-key, .inline-field, .properties, .dataview-error, .kanban .count';
  const NO_SC = SKIP + ', h1, h2, h3, h4, h5, h6, strong, b, .callout-title, .doc-backlinks, .lead-in, .sc, .fallback-title, a.field-chip, sup, .attribution-dash';
  const BLOCK = /^(P|LI|H[1-6]|BLOCKQUOTE|TD|TH|DT|DD|FIGCAPTION|CAPTION|DIV|SECTION|ASIDE|DETAILS|SUMMARY|FOOTER|MAIN|UL|OL|TABLE)$/;

  // ---- strings -------------------------------------------------------------------------
  const OPENER = /[\s(\[{\u2014\u2013\/\u00a0\u2018\u201c-]/;
  const WORD = /[\p{L}\p{N}]/u;

  /** Straight punctuation to typographer's punctuation. `prev` is the character before
   *  `s` (across inline markup), so a quote right after </em> still knows where it is. */
  function smarten(s, prev = ' ') {
    s = s.replace(/(^|[^-])---(?!-)/g, '$1\u2014')                // em dash
      .replace(/(\s)--(\s)/g, '$1\u2014$2')                        // spaced -- reads as an em dash
      .replace(/(\d)--(?=\d)/g, '$1\u2013')                        // 1914--1918
      .replace(/(^|[^-!<])--(?![->])/g, '$1\u2013')                // en dash
      .replace(/([\p{L}\p{N}]) - (?=[\p{L}\p{N}])/gu, '$1 \u2013 ') // spaced hyphen: en dash
      .replace(/\.\.\.(?!\.)|\. \. \./g, '\u2026');                // ellipsis
    let out = '';
    for (let i = 0; i < s.length; i++) {
      const c = s[i], p = out ? out[out.length - 1] : prev, rest = s.slice(i + 1, i + 5);
      if (c === '"') out += (!p || OPENER.test(p)) ? '\u201c' : '\u201d';
      else if (c === "'") {
        if (p && WORD.test(p)) out += '\u2019';                              // don't, Requests’
        else if (/^(\d\ds|\d\d\b|tis\b|twas\b|em\b|n\b|cause\b)/i.test(rest)) out += '\u2019';   // ’90s, ’em, rock ’n’ roll
        else if (!p || OPENER.test(p)) out += '\u2018';
        else out += '\u2019';
      } else out += c;
    }
    return out;
  }

  /** Ties: no line may end on "a", "I", "§" or "Dr."; the next word comes along. */
  function tie(s) {
    return s.replace(/(^|[\s(\u2014\u201c])(a|A|an|An|I|&|§|¶|Mr\.|Mrs\.|Ms\.|Dr\.|St\.|Mt\.|No\.|no\.|vol\.|ch\.|p\.|pp\.|fig\.|Fig\.|cf\.|vs\.) (?=\S)/g, '$1$2\u00a0')
      .replace(/(\d) (%|percent|am|pm|AM|PM|BC|AD|BCE|CE|km|kg|mm|cm|ms|MB|GB|TB|KB)\b/g, '$1\u00a0$2');
  }

  const ROMAN = /^(?=[IVX]+$)X{0,3}(IX|IV|V?I{0,3})$/;
  /** Runs of two or more capitals (PSF, HTTP, APIs, AT&T, MP3) → spans of true small caps.
   *  Skips roman numerals (World War II) and shouting (three capital words in a row). */
  function smallCapsRanges(s) {
    if (/\b[A-Z]{2,}\W+[A-Z]{2,}\W+[A-Z]{2,}\b/.test(s)) return [];
    const out = [];
    const re = /\b[A-Z](?:[A-Z0-9&]*[A-Z0-9])?(?=s?\b)/g;
    let m;
    while ((m = re.exec(s))) {
      const w = m[0];
      if ((w.match(/[A-Z]/g) || []).length < 2 || ROMAN.test(w)) continue;
      out.push([m.index, m.index + w.length]);
    }
    return out;
  }

  // ---- DOM -----------------------------------------------------------------------------
  const blockOf = (n) => { let e = n.parentNode; while (e && !(e.nodeType === 1 && BLOCK.test(e.tagName))) e = e.parentNode; return e; };

  function textNodes(root, skip) {
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (n) => (n.parentElement && n.parentElement.closest(skip)) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
    });
    const out = [];
    while (w.nextNode()) out.push(w.currentNode);
    return out;
  }

  function smartenDOM(root) {
    let prev = ' ', block = null;
    for (const n of textNodes(root, SKIP)) {
      const b = blockOf(n);
      if (b !== block) { block = b; prev = ' '; }
      const v = n.nodeValue;
      if (!v) continue;
      const s = tie(smarten(v, prev));
      if (s !== v) n.nodeValue = s;
      prev = s[s.length - 1] || prev;
    }
  }

  function smallCapsDOM(root) {
    for (const n of textNodes(root, NO_SC)) {
      const r = smallCapsRanges(n.nodeValue);
      if (!r.length) continue;
      const f = document.createDocumentFragment();
      let at = 0;
      for (const [a, b] of r) {
        if (a > at) f.appendChild(document.createTextNode(n.nodeValue.slice(at, a)));
        const abbr = document.createElement('abbr');
        abbr.className = 'sc';
        abbr.textContent = n.nodeValue.slice(a, b);
        f.appendChild(abbr);
        at = b;
      }
      if (at < n.nodeValue.length) f.appendChild(document.createTextNode(n.nodeValue.slice(at)));
      n.parentNode.replaceChild(f, n);
    }
  }

  // Optical margin kerning for quotes inside a paragraph: a push/pull pair that cancels
  // mid-line, so an opening quote that lands at the start of a line hangs into the margin
  // (the paragraph's own first quote is handled by `hanging-punctuation: first`).
  function hangQuotes(root) {
    for (const n of textNodes(root, SKIP + ', h1, h2, h3, h4, h5, h6, td, th, .sidenote, .callout-title, .doc-backlinks')) {
      const v = n.nodeValue;
      if (!/\s[\u201c\u2018]/.test(v) || !n.parentElement.closest('p, li, blockquote')) continue;
      const f = document.createDocumentFragment();
      const parts = v.split(/(\s)([\u201c\u2018])/);
      for (let i = 0; i < parts.length; i++) {
        if (i % 3 === 2) {
          const kind = parts[i] === '\u201c' ? 'dq' : 'sq';
          const pull = document.createElement('span'); pull.className = 'pull-' + kind; pull.textContent = parts[i];
          f.appendChild(pull);
        } else if (i % 3 === 1) {
          const push = document.createElement('span'); push.className = 'push-' + (parts[i + 1] === '\u201c' ? 'dq' : 'sq');
          f.appendChild(push); f.appendChild(document.createTextNode(parts[i]));
        } else if (parts[i]) f.appendChild(document.createTextNode(parts[i]));
      }
      n.parentNode.replaceChild(f, n);
    }
  }

  const words = (el) => (el.textContent.match(/[\p{L}\p{N}’']+/gu) || []).length;

  /** The opening: the first real paragraph after the title gets a small-caps lead-in
   *  (its first few words, Tufte's "newthought") or a drop cap. Short notes don't. */
  function opening(page, mode) {
    if (mode === 'none') return;
    const h1 = page.querySelector(':scope > h1');
    let el = h1 ? h1.nextElementSibling : page.firstElementChild;
    for (let i = 0; el && i < 4; i++, el = el.nextElementSibling) {
      if (el.tagName === 'P' && words(el) >= 15) break;
      if (el.tagName === 'P') continue;                              // a date line, a byline
      if (el.matches('.properties, blockquote.epigraph, .epigraph')) continue;
      el = null; break;
    }
    if (!el || el.tagName !== 'P' || words(el) < 15) return;
    const first = el.firstChild;
    if (!first || first.nodeType !== 3 || !/^\s*\S/.test(first.nodeValue)) return;
    // The first few words (up to four), stopping early at a clause break.
    const re = /\s*\S+/g;
    let lead = '', m, n = 0;
    while (n < 4 && (m = re.exec(first.nodeValue))) {
      lead = first.nodeValue.slice(0, re.lastIndex); n++;
      if (/[,;:.!?\u2014\u2026]$/.test(m[0])) break;
    }
    if (!lead.trim()) return;
    // A drop cap wants a letter; a paragraph that opens on a quote gets the lead-in instead.
    if (mode === 'dropcap' && !/^\s*[\p{L}\p{N}]/u.test(lead)) mode = 'smallcaps';
    el.classList.add('opening', mode === 'dropcap' ? 'has-dropcap' : 'has-lead-in');
    const span = document.createElement('span');
    span.className = 'lead-in';
    span.textContent = lead;
    first.nodeValue = first.nodeValue.slice(lead.length);
    el.insertBefore(span, first);
  }

  /** Blockquotes whose last line begins with a dash carry an attribution; one that opens
   *  the note (right under the title) is an epigraph. */
  function quotes(page) {
    page.querySelectorAll('blockquote').forEach(bq => {
      if (bq.closest('.callout, .sidenote')) return;
      const last = bq.lastElementChild;
      if (last && last.tagName === 'P') {
        const html = last.innerHTML;
        const m = /(?:^|<br>\s*)\s*(?:\u2014|\u2015|\u2013|--?)\s*([^<]*(?:<(?!br)[^>]*>[^<]*)*)$/.exec(html);
        if (m && m[1].trim() && m[1].length < 160) {
          const f = document.createElement('footer');
          f.className = 'attribution';
          f.innerHTML = `<span class="attribution-dash">\u2014</span> ${m[1].trim()}`;
          const before = html.slice(0, m.index).trim();
          if (before) last.innerHTML = before; else last.remove();
          bq.appendChild(f);
        }
      }
      const prev = bq.previousElementSibling;
      const atTop = prev && (prev.tagName === 'H1' || (prev.tagName === 'P' && words(prev) < 12 && prev.previousElementSibling && prev.previousElementSibling.tagName === 'H1'));
      if (atTop && bq.parentElement && bq.parentElement.id === 'page') bq.classList.add('epigraph');
    });
  }

  const isFile = (s) => !s || /\.(png|jpe?g|gif|webp|svg|avif|heic|bmp|tiff?)$/i.test(s.trim()) || /^(image|img|screenshot|pasted image)\b/i.test(s.trim());

  /** An image alone in its paragraph is a figure; a title (or a real alt text) is its caption.
   *  A paragraph starting "Table:" next to a table becomes that table's caption. */
  function figures(page) {
    let nFig = 0, nTab = 0;
    page.querySelectorAll('p').forEach(p => {
      if (p.closest('.sidenote, .markdown-embed, .callout, td, th, li')) return;
      const kids = [...p.childNodes].filter(n => !(n.nodeType === 3 && !n.nodeValue.trim()) && !(n.nodeType === 1 && n.tagName === 'BR'));
      if (kids.length !== 1 || kids[0].nodeType !== 1 || kids[0].tagName !== 'IMG' || kids[0].hasAttribute('width')) return;
      const img = kids[0];
      const fig = document.createElement('figure');
      for (const a of ['data-line', 'data-lines']) if (p.hasAttribute(a)) fig.setAttribute(a, p.getAttribute(a));
      fig.appendChild(img);
      const cap = img.getAttribute('title') || (!isFile(img.getAttribute('alt')) ? img.getAttribute('alt') : '');
      if (cap) {
        const fc = document.createElement('figcaption');
        fc.innerHTML = `<span class="fig-label">Figure ${++nFig}.</span> ` + escape(smarten(cap));
        fig.appendChild(fc);
      }
      p.replaceWith(fig);
    });
    page.querySelectorAll('.table-wrap').forEach(w => {
      const table = w.querySelector('table');
      if (!table) return;
      for (const sib of [w.previousElementSibling, w.nextElementSibling]) {
        if (!sib || sib.tagName !== 'P') continue;
        const m = /^\s*(?:Table(?:\s+\d+)?[.:]|:)\s+/i.exec(sib.textContent);
        if (!m) continue;
        const cap = document.createElement('caption');
        cap.innerHTML = sib.innerHTML.replace(/^\s*(?:Table(?:\s+\d+)?[.:]|:)\s+/i, `<span class="fig-label">Table ${++nTab}.</span> `);
        table.insertBefore(cap, table.firstChild);
        sib.remove();
        break;
      }
      numericColumns(table);
    });
  }
  const escape = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  const NUM = /^[\s(]*[-+\u2212\u2013]?[$€£¥]?\s?\d[\d,.\u2009\u00a0 ]*(%|[kKMB]|x|×)?\)?\s*$/;
  const DATE = /^\s*(?:\d{4}-\d{2}-\d{2}|\d{1,2}[./]\d{1,2}[./]\d{2,4})\s*$/;
  const SHORT = 12;
  /** A date, a numeric cell, or a short token with no spaces — keep it on one line. */
  function isCompact(s) {
    const t = String(s || '').trim();
    if (!t) return true;
    if (NUM.test(t) || DATE.test(t)) return true;
    return t.length <= SHORT && !/\s/.test(t);
  }
  /** Columns of figures align on the right in tabular lining numerals (booktabs habit). */
  function numericColumns(table) {
    const rows = [...table.querySelectorAll('tbody tr')];
    if (!rows.length) return;
    const n = Math.max(...rows.map(r => r.cells.length));
    for (let c = 0; c < n; c++) {
      const cells = rows.map(r => r.cells[c]).filter(Boolean);
      const filled = cells.filter(td => td.textContent.trim() && !/^[\u2014\u2013-]$/.test(td.textContent.trim()));
      if (!filled.length || !filled.every(td => NUM.test(td.textContent))) continue;
      cells.forEach(td => td.classList.add('num'));
      const th = table.querySelector(`thead tr`) && table.querySelector('thead tr').cells[c];
      if (th) th.classList.add('num');
    }
  }

  /** Mark compact columns (dates, numbers, short tokens) so CSS can nowrap them. */
  function compactColumns(table) {
    const rows = [...table.querySelectorAll('tr')];
    if (!rows.length) return;
    const n = Math.max(...rows.map(r => r.cells.length));
    for (let c = 0; c < n; c++) {
      const cells = rows.map(r => r.cells[c]).filter(Boolean);
      const filled = cells.filter(td => td.textContent.trim());
      if (!filled.length || !filled.every(td => isCompact(td.textContent))) continue;
      cells.forEach(td => td.classList.add('nowrap'));
    }
  }

  /** Always run, even when Typeset reading is off: column classes drive the CSS. */
  function layoutTables(page) {
    if (!page || typeof page.querySelectorAll !== 'function') return;
    page.querySelectorAll('.table-wrap table').forEach(table => {
      numericColumns(table);
      compactColumns(table);
    });
    sizeWideTables(page);
  }

  /** Mark a wrap as scrollable and, if the user can still scroll right,
      leave off `.at-end` so the CSS fade shows. Hidden when nothing overflows. */
  function updateScrollCue(el) {
    if (!el || el.clientWidth == null) return;
    const max = el.scrollWidth - el.clientWidth;
    const overflow = max > 1;
    el.classList.toggle('is-scrollable', overflow);
    el.classList.toggle('at-end', !overflow || el.scrollLeft >= max - 1);
    if (overflow && !el._onyxScrollCue) {
      el.addEventListener('scroll', () => updateScrollCue(el), { passive: true });
      el._onyxScrollCue = true;
    }
  }

  /** Bleed / scroll only when the table's min-content (8em floors + nowrap
      natural widths) exceeds the measure. Never size the table to max-content,
      or a wrapping description will refuse to wrap and spill into a scroll. */
  function sizeWideTables(page) {
    if (!page || typeof page.querySelectorAll !== 'function') return;
    page.querySelectorAll('.table-wrap').forEach(wrap => {
      const table = wrap.querySelector('table');
      if (!table) return;
      wrap.classList.remove('table-wide', 'is-scrollable', 'at-end');
      const available = wrap.clientWidth;
      if (!available) { updateScrollCue(wrap); return; }
      const prev = table.style.width;
      table.style.width = 'min-content';
      const min = table.getBoundingClientRect().width;
      table.style.width = prev;
      if (min > available + 0.5) wrap.classList.add('table-wide');
      updateScrollCue(wrap);
    });
  }

  /** Language for hyphenation dictionaries: frontmatter `lang` or `language`, else English. */
  function language(props) {
    const p = (props || []).find(p => /^(lang|language)$/i.test(p.key));
    const v = p && String(p.value || '').trim();
    return v && /^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$/i.test(v) ? v : 'en';
  }

  function apply(page, opts) {
    opts = opts || {};
    // Hyphenation dictionaries key off lang on the reader root; default English.
    const lang = language(opts.props);
    page.lang = lang;
    const doc = page.ownerDocument;
    if (doc && doc.documentElement) doc.documentElement.lang = lang;
    if (doc && doc.body) doc.body.lang = lang;
    if (!opts.on) { layoutTables(page); return; }
    smartenDOM(page);
    quotes(page);
    // A short line right under the title (or under its epigraph) is a date or byline: \date.
    const h1 = page.querySelector(':scope > h1');
    let by = h1 && h1.nextElementSibling;
    if (by && by.matches('blockquote.epigraph')) by = by.nextElementSibling;
    if (by && by.tagName === 'P' && words(by) < 15 && !by.querySelector('img')) by.classList.add('byline');
    figures(page);
    if (opts.smallCaps !== false) smallCapsDOM(page);
    hangQuotes(page);
    opening(page, opts.opening || 'smallcaps');
    layoutTables(page);
  }

  window.OnyxTypeset = { apply, smarten, tie, smallCapsRanges, language, NUM, DATE, isCompact, layoutTables, sizeWideTables, updateScrollCue };
})();
