// Obsidian-style $inline$ / $$display$$ math. Finds delimiters (skipping code
// and escaped \$), then protects them from Markdown so KaTeX can typeset them.
// Attaches to window.OnyxMath for the reader and for Tests/reader.
(function (root) {
  function isEscaped(src, i) {
    let n = 0;
    while (i - n - 1 >= 0 && src[i - n - 1] === '\\') n++;
    return n % 2 === 1;
  }

  function atBol(src, i) {
    return i === 0 || src[i - 1] === '\n' || src[i - 1] === '\r';
  }

  // Fenced code starting at i (beginning of a line). Returns the index after
  // the closing fence, or after the rest of the document if it never closes.
  function skipFence(src, i) {
    if (!atBol(src, i)) return -1;
    const m = /^( {0,3})(```+|~~~+)/.exec(src.slice(i));
    if (!m) return -1;
    const fence = m[2];
    const startLineEnd = src.indexOf('\n', i);
    let j = startLineEnd < 0 ? src.length : startLineEnd + 1;
    const closer = new RegExp('^ {0,3}' + fence[0] + '{' + fence.length + ',}\\s*$', 'm');
    const rest = src.slice(j);
    const cm = closer.exec(rest);
    if (!cm) return src.length;
    const closeAt = j + cm.index + cm[0].length;
    const nl = src.indexOf('\n', closeAt);
    return nl < 0 ? src.length : nl + 1;
  }

  // Inline code span starting at a backtick. Unclosed spans are not code.
  function skipInlineCode(src, i) {
    if (src[i] !== '`') return -1;
    // A fence at bol is handled elsewhere.
    let n = 0;
    while (src[i + n] === '`') n++;
    if (n >= 3 && atBol(src, i)) return -1;
    const rest = src.slice(i + n);
    const re = new RegExp('(?<!`)' + '`'.repeat(n) + '(?!`)');
    const m = re.exec(rest);
    if (!m) return -1;
    return i + n + m.index + n;
  }

  // Indented code block: after a blank line (or start), lines starting with
  // four spaces or a tab. Returns end index, or -1 if this isn't one.
  function skipIndented(src, i) {
    if (!atBol(src, i)) return -1;
    if (i > 0) {
      let k = i - 1;
      if (src[k] === '\n') k--;
      if (k >= 0 && src[k] === '\r') k--;
      if (k >= 0 && src[k] !== '\n') return -1;
    }
    if (!(src.startsWith('    ', i) || src[i] === '\t')) return -1;
    let j = i;
    while (j < src.length) {
      const nl = src.indexOf('\n', j);
      const end = nl < 0 ? src.length : nl + 1;
      const line = src.slice(j, nl < 0 ? src.length : nl);
      if (line.trim() === '') { j = end; continue; }
      if (line.startsWith('    ') || line.startsWith('\t')) { j = end; continue; }
      break;
    }
    return j > i ? j : -1;
  }

  function skipCode(src, i) {
    const f = skipFence(src, i);
    if (f >= 0) return f;
    const ind = skipIndented(src, i);
    if (ind >= 0) return ind;
    const c = skipInlineCode(src, i);
    if (c >= 0) return c;
    return -1;
  }

  // Horizontal whitespace immediately inside the delimiter is not allowed
  // (Obsidian). Newlines are allowed for $$ so multi-line display blocks work.
  function tightInside(src, i, isOpen, display) {
    const ch = isOpen ? src[i] : src[i - 1];
    if (ch === undefined) return false;
    if (ch === ' ' || ch === '\t') return false;
    if (!display && (ch === '\n' || ch === '\r')) return false;
    return true;
  }

  function findClose(src, from, delim, display) {
    let j = from;
    while (j < src.length) {
      if (src[j] === '$' && !isEscaped(src, j)) {
        if (delim === 2 && src[j + 1] === '$') return j;
        if (delim === 1 && src[j + 1] !== '$') return j;
      }
      if (!display && (src[j] === '\n' || src[j] === '\r')) return -1;
      j++;
    }
    return -1;
  }

  function find(src) {
    const hits = [];
    let i = 0;
    while (i < src.length) {
      const skip = skipCode(src, i);
      if (skip > i) { i = skip; continue; }
      if (src[i] === '$' && !isEscaped(src, i)) {
        const display = src[i + 1] === '$';
        const delim = display ? 2 : 1;
        const after = i + delim;
        if (after > src.length) { i += 1; continue; }
        if (!tightInside(src, after, true, display)) { i += delim; continue; }
        const close = findClose(src, after, delim, display);
        if (close < 0 || close === after) { i += delim; continue; }
        if (!tightInside(src, close, false, display)) { i += delim; continue; }
        // A closing $ followed by a digit is currency ($20), not math.
        if (!display && /\d/.test(src[close + delim] || '')) { i += 1; continue; }
        hits.push({ start: i, end: close + delim, display, tex: src.slice(after, close) });
        i = close + delim;
        continue;
      }
      i++;
    }
    return hits;
  }

  const MARK = (n) => '§§ONYXMATH' + n + '§§';
  const MARK_RE = /§§ONYXMATH(\d+)§§/g;

  function protect(src) {
    const slots = find(src);
    if (!slots.length) return { text: src, slots: [] };
    let out = '', last = 0;
    slots.forEach((s, n) => {
      out += src.slice(last, s.start);
      const newlines = (s.tex.match(/\n/g) || []).length;
      out += MARK(n) + '\n'.repeat(newlines);
      last = s.end;
    });
    out += src.slice(last);
    return { text: out, slots };
  }

  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function renderSlot(slot) {
    const tex = slot.tex.replace(/^\n+|\n+$/g, '');
    const kind = slot.display ? 'display' : 'inline';
    const tag = slot.display ? 'div' : 'span';
    if (root.katex) {
      try {
        const html = root.katex.renderToString(tex, {
          displayMode: !!slot.display,
          throwOnError: true,
          output: 'html',
          trust: false,
          strict: 'ignore',
        });
        return `<${tag} class="math ${kind}">${html}</${tag}>`;
      } catch (err) {
        const msg = (err && err.message) ? String(err.message) : 'Invalid TeX';
        return `<${tag} class="math math-error ${kind}" title="${esc(msg)}">${esc(tex)}</${tag}>`;
      }
    }
    return `<${tag} class="math ${kind}">${esc(tex)}</${tag}>`;
  }

  function restore(html, slots) {
    if (!slots || !slots.length) return html;
    return html.replace(MARK_RE, (_, n) => {
      const slot = slots[+n];
      return slot ? renderSlot(slot) : '';
    });
  }

  root.OnyxMath = { find, protect, restore, renderSlot };
})(typeof window !== 'undefined' ? window : globalThis);
