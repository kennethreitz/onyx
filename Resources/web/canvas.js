// Onyx canvas: Obsidian Canvas / JSON Canvas 1.0 (https://jsoncanvas.org).
// Swift hands us the file text plus every card's resolved content; we draw, pan, zoom and
// edit, and post the whole document back as JSON.stringify(doc). Nodes and edges are kept as
// the parsed objects, so ids, key order and fields we don't know about are never lost.
(function () {
  const post = (m) => window.webkit && window.webkit.messageHandlers.onyx.postMessage(m);
  const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const $ = (id) => document.getElementById(id);
  const stage = $('stage'), world = $('world'), groupsEl = $('groups'), nodesEl = $('nodes'), edgesEl = $('edges'), labelsEl = $('labels');
  const menu = $('menu'), picker = $('picker'), pickQ = $('pick-q'), pickList = $('pick-list'), marquee = $('marquee'), hint = $('hint');
  const SVG = 'http://www.w3.org/2000/svg';

  // Obsidian's preset colors 1–6 (red, orange, yellow, green, cyan, purple), a touch muted.
  const PRESETS = { '1': [214, 74, 74], '2': [222, 128, 46], '3': [206, 164, 34], '4': [72, 160, 96], '5': [52, 160, 172], '6': [132, 100, 200] };
  function rgb(color) {
    if (!color) return null;
    if (PRESETS[color]) return PRESETS[color];
    const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(color).trim());
    if (!m) return null;
    let h = m[1]; if (h.length === 3) h = h.split('').map(c => c + c).join('');
    return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
  }

  let P = { files: {}, links: {}, embeds: {}, base: '' };
  let doc = { nodes: [], edges: [] };
  let path = null, editable = true, broken = false;
  let cam = { x: 0, y: 0, z: 1 };
  const selN = new Set(), selE = new Set();
  let undoStack = [], redoStack = [];
  let editing = null;          // { id, ta } while a text card is being typed in
  let mode = null;             // current pointer gesture
  let saveTimer = 0;
  let lastWorldPoint = { x: 0, y: 0 };

  const nodes = () => (Array.isArray(doc.nodes) ? doc.nodes : (doc.nodes = []));
  const edges = () => (Array.isArray(doc.edges) ? doc.edges : (doc.edges = []));
  const byId = (id) => nodes().find(n => n.id === id);
  const num = (v, d) => (typeof v === 'number' && isFinite(v) ? v : d);
  const box = (n) => ({ x: num(n.x, 0), y: num(n.y, 0), w: Math.max(1, num(n.width, 250)), h: Math.max(1, num(n.height, 60)) });
  function newId() {
    const a = new Uint8Array(8); (window.crypto || {}).getRandomValues ? crypto.getRandomValues(a) : a.forEach((_, i) => a[i] = Math.random() * 256 | 0);
    let id; do { id = [...a].map(b => b.toString(16).padStart(2, '0')).join(''); a[0] ^= 1; } while (byId(id) || edges().some(e => e.id === id));
    return id;
  }

  // MARK: camera

  function applyCam() {
    world.style.transform = `translate(${cam.x}px, ${cam.y}px) scale(${cam.z})`;
    world.style.setProperty('--inv', 1 / cam.z);
    document.body.style.setProperty('--inv', 1 / cam.z);
    const g = 22 * cam.z;
    stage.style.backgroundSize = g < 9 ? '0 0' : `${g}px ${g}px`;
    stage.style.backgroundPosition = `${cam.x}px ${cam.y}px`;
    drawEdges();
  }
  const toWorld = (cx, cy) => ({ x: (cx - cam.x) / cam.z, y: (cy - cam.y) / cam.z });
  function zoomAt(cx, cy, factor) {
    const z = Math.min(4, Math.max(0.08, cam.z * factor));
    const w = toWorld(cx, cy);
    cam.z = z; cam.x = cx - w.x * z; cam.y = cy - w.y * z;
    applyCam();
  }
  function bounds(list) {
    if (!list.length) return null;
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const n of list) { const b = box(n); x0 = Math.min(x0, b.x); y0 = Math.min(y0, b.y); x1 = Math.max(x1, b.x + b.w); y1 = Math.max(y1, b.y + b.h); }
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  }
  function fit(list, animate) {
    const b = bounds(list || nodes());
    const W = window.innerWidth, H = window.innerHeight, top = 40, pad = 48;
    if (!b) { cam = { x: W / 2, y: H / 2, z: 1 }; applyCam(); return; }
    const z = Math.min(1, Math.max(0.08, Math.min((W - pad * 2) / b.w, (H - top - pad * 2) / b.h)));
    const target = { z, x: W / 2 - (b.x + b.w / 2) * z, y: top + (H - top) / 2 - (b.y + b.h / 2) * z };
    if (!animate) { cam = target; applyCam(); return; }
    const from = { ...cam }, t0 = performance.now();
    const step = (t) => {
      const k = Math.min(1, (t - t0) / 220), e = 1 - Math.pow(1 - k, 3);
      cam = { x: from.x + (target.x - from.x) * e, y: from.y + (target.y - from.y) * e, z: from.z + (target.z - from.z) * e };
      applyCam(); if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  // MARK: rendering

  function fileInfo(n) { return P.files[(n.file || '') + (n.subpath || '')] || P.files[n.file || ''] || null; }

  function cardHTML(n) {
    switch (n.type) {
      case 'text':
        return `<div class="body"><div class="canvas-md markdown-preview-view">${Onyx.fragment(n.text || '', P)}</div></div>`;
      case 'file': {
        const f = fileInfo(n);
        const label = `<div class="file-label">${esc((n.file || '').split('/').pop().replace(/\.md$/i, '') + (n.subpath || ''))}</div>`;
        if (!f) return label + `<div class="body"><div class="placeholder">Loading…</div></div>`;
        switch (f.type) {
          case 'note': {
            const r = f.reader || {};
            let html = Onyx.fragment(r.markdown || '', r);
            html = html.replace(/<div class="onyx-dataview" data-i="(\d+)"><\/div>/g, (_, i) => (r.dataview || [])[+i] || '');
            return label + `<div class="body"><div class="canvas-md markdown-preview-view">${html}</div></div>`;
          }
          case 'image': return label + `<div class="body"><img class="media" draggable="false" src="${esc(f.url)}" alt=""></div>`;
          case 'pdf': return label + `<div class="body"><embed class="media" src="${esc(f.url)}" type="application/pdf"></div>`;
          case 'video': return label + `<div class="body"><video class="media" controls src="${esc(f.url)}"></video></div>`;
          case 'audio': return label + `<div class="body"><div class="placeholder"><b>${esc(f.name)}</b><audio controls src="${esc(f.url)}"></audio></div></div>`;
          case 'canvas': return label + `<div class="body"><div class="placeholder"><b>${esc(f.name)}</b>Canvas · ${esc(f.detail || '')}<br>double-click to open</div></div>`;
          case 'missing': return label + `<div class="body"><div class="placeholder missing">Not found<br>${esc(n.file)}</div></div>`;
          default: return label + `<div class="body"><div class="placeholder"><b>${esc(f.name)}</b>double-click to open</div></div>`;
        }
      }
      case 'link': {
        let host = n.url || '';
        try { host = new URL(n.url).hostname.replace(/^www\./, ''); } catch (e) { }
        return `<div class="body"><div class="placeholder"><span class="host">${esc(host)}</span><span class="url">${esc(n.url || '')}</span></div></div>`;
      }
      case 'group': {
        const bg = n.background ? ` style="background-image:url('${esc('onyx://vault/' + encodeURI(n.background))}')"` : '';
        return `<div class="group-label">${esc(n.label || '')}</div><div class="body"${bg}></div>`;
      }
      default:
        return `<div class="body"><div class="placeholder">${esc(n.type || 'card')}</div></div>`;
    }
  }

  const HANDLES = '<i class="h-side top" data-side="top"></i><i class="h-side right" data-side="right"></i><i class="h-side bottom" data-side="bottom"></i><i class="h-side left" data-side="left"></i>' +
    ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'].map(d => `<i class="h-resize ${d}" data-dir="${d}"></i>`).join('');

  function nodeEl(id) { return document.querySelector(`.node[data-id="${CSS.escape(id)}"]`); }
  function layoutNode(n, el) {
    el = el || nodeEl(n.id); if (!el) return;
    const b = box(n);
    el.style.left = b.x + 'px'; el.style.top = b.y + 'px'; el.style.width = b.w + 'px'; el.style.height = b.h + 'px';
  }
  function decorateNode(n, el) {
    const c = rgb(n.color);
    el.className = `node type-${n.type || 'unknown'}` + (c ? ' colored' : '') + (selN.has(n.id) ? ' selected' : '') +
      (n.type === 'text' || (n.type === 'file' && (fileInfo(n) || {}).type === 'note') ? ' scroll' : '');
    if (c) el.style.setProperty('--c', c.join(', ')); else el.style.removeProperty('--c');
  }
  function renderNode(n) {
    const el = document.createElement('div');
    el.dataset.id = n.id;
    el.innerHTML = cardHTML(n) + (n.type === 'group' ? ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'].map(d => `<i class="h-resize ${d}" data-dir="${d}"></i>`).join('') : HANDLES);
    decorateNode(n, el); layoutNode(n, el);
    return el;
  }
  function render() {
    if (editing) stopEditing(true, true);
    groupsEl.textContent = ''; nodesEl.textContent = '';
    for (const n of nodes()) (n.type === 'group' ? groupsEl : nodesEl).appendChild(renderNode(n));
    for (const id of [...selN]) if (!byId(id)) selN.delete(id);
    for (const id of [...selE]) if (!edges().some(e => e.id === id)) selE.delete(id);
    drawEdges();
  }
  function rerenderNode(n) {
    const old = nodeEl(n.id); if (!old) return;
    const el = renderNode(n);
    const body = old.querySelector('.body'), top = body ? body.scrollTop : 0;
    old.replaceWith(el);
    const nb = el.querySelector('.body'); if (nb) nb.scrollTop = top;
  }
  function refreshSelection() {
    for (const n of nodes()) { const el = nodeEl(n.id); if (el) el.classList.toggle('selected', selN.has(n.id)); }
    drawEdges();
  }

  // edges
  const NORMAL = { top: [0, -1], bottom: [0, 1], left: [-1, 0], right: [1, 0] };
  function sidePoint(n, side) {
    const b = box(n);
    switch (side) {
      case 'top': return [b.x + b.w / 2, b.y];
      case 'bottom': return [b.x + b.w / 2, b.y + b.h];
      case 'left': return [b.x, b.y + b.h / 2];
      default: return [b.x + b.w, b.y + b.h / 2];
    }
  }
  function autoSides(a, b) {
    const A = box(a), B = box(b);
    const dx = (B.x + B.w / 2) - (A.x + A.w / 2), dy = (B.y + B.h / 2) - (A.y + A.h / 2);
    if (Math.abs(dx) * A.h > Math.abs(dy) * A.w) return dx > 0 ? ['right', 'left'] : ['left', 'right'];
    return dy > 0 ? ['bottom', 'top'] : ['top', 'bottom'];
  }
  function edgeGeom(e) {
    const a = byId(e.fromNode), b = byId(e.toNode);
    if (!a || !b) return null;
    const auto = autoSides(a, b);
    const fs = NORMAL[e.fromSide] ? e.fromSide : auto[0], ts = NORMAL[e.toSide] ? e.toSide : auto[1];
    return curve(sidePoint(a, fs), fs, sidePoint(b, ts), ts);
  }
  function curve(p1, s1, p2, s2) {
    const d = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
    const off = Math.max(30, Math.min(220, d * 0.45));
    const n1 = NORMAL[s1] || [0, 0], n2 = NORMAL[s2] || [0, 0];
    const c1 = [p1[0] + n1[0] * off, p1[1] + n1[1] * off], c2 = [p2[0] + n2[0] * off, p2[1] + n2[1] * off];
    const at = (t) => { const u = 1 - t; return [u*u*u*p1[0] + 3*u*u*t*c1[0] + 3*u*t*t*c2[0] + t*t*t*p2[0], u*u*u*p1[1] + 3*u*u*t*c1[1] + 3*u*t*t*c2[1] + t*t*t*p2[1]]; };
    return { p1, p2, c1, c2, n1, n2, mid: at(0.5) };
  }
  function arrowPath(tip, n, size) {
    // the arrow points into the card: from tip outward along the side normal
    const bx = tip[0] + n[0] * size, by = tip[1] + n[1] * size, px = -n[1] * size * 0.5, py = n[0] * size * 0.5;
    return `M${tip[0]},${tip[1]} L${bx + px},${by + py} L${bx - px},${by - py} Z`;
  }
  function drawEdges(temp) {
    edgesEl.textContent = ''; labelsEl.textContent = '';
    const sw = Math.max(1.6, 1.6 / Math.sqrt(cam.z)), A = 9 * Math.max(1, 1 / Math.sqrt(cam.z * 1.4));
    for (const e of edges()) {
      const g = edgeGeom(e); if (!g) continue;
      const toArrow = (e.toEnd || 'arrow') !== 'none', fromArrow = e.fromEnd === 'arrow';
      const s = toArrow ? [g.p2[0] + g.n2[0] * A * 0.8, g.p2[1] + g.n2[1] * A * 0.8] : g.p2;
      const f = fromArrow ? [g.p1[0] + g.n1[0] * A * 0.8, g.p1[1] + g.n1[1] * A * 0.8] : g.p1;
      const d = `M${f[0]},${f[1]} C${g.c1[0]},${g.c1[1]} ${g.c2[0]},${g.c2[1]} ${s[0]},${s[1]}`;
      const grp = document.createElementNS(SVG, 'g');
      const c = rgb(e.color);
      grp.setAttribute('class', 'edge' + (c ? ' colored' : '') + (selE.has(e.id) ? ' selected' : ''));
      if (c) grp.style.setProperty('--c', c.join(', '));
      grp.dataset.id = e.id;
      const line = document.createElementNS(SVG, 'path'); line.setAttribute('class', 'line'); line.setAttribute('d', d); line.setAttribute('stroke-width', selE.has(e.id) ? sw * 1.6 : sw);
      const hit = document.createElementNS(SVG, 'path'); hit.setAttribute('class', 'hit'); hit.setAttribute('d', d); hit.setAttribute('stroke-width', 14 / cam.z); hit.dataset.edge = e.id;
      grp.appendChild(line);
      if (toArrow) { const a = document.createElementNS(SVG, 'path'); a.setAttribute('class', 'arrow'); a.setAttribute('d', arrowPath(g.p2, g.n2, A)); grp.appendChild(a); }
      if (fromArrow) { const a = document.createElementNS(SVG, 'path'); a.setAttribute('class', 'arrow'); a.setAttribute('d', arrowPath(g.p1, g.n1, A)); grp.appendChild(a); }
      grp.appendChild(hit);
      edgesEl.appendChild(grp);
      if (e.label) {
        const l = document.createElement('div');
        l.className = 'edge-label' + (selE.has(e.id) ? ' selected' : '');
        l.dataset.edge = e.id; l.textContent = e.label;
        l.style.left = g.mid[0] + 'px'; l.style.top = g.mid[1] + 'px';
        if (c) l.style.color = `rgb(${c.join(',')})`;
        labelsEl.appendChild(l);
      }
    }
    if (temp) {
      const t = document.createElementNS(SVG, 'path'); t.setAttribute('class', 'temp');
      const g = curve(temp.p1, temp.s1, temp.p2, temp.s2 || null);
      t.setAttribute('d', `M${g.p1[0]},${g.p1[1]} C${g.c1[0]},${g.c1[1]} ${g.c2[0]},${g.c2[1]} ${g.p2[0]},${g.p2[1]}`);
      t.setAttribute('stroke-width', 1.6 / cam.z);
      edgesEl.appendChild(t);
    }
  }

  // MARK: document changes

  function snapshot() { return JSON.stringify(doc); }
  function checkpoint() { undoStack.push(snapshot()); if (undoStack.length > 200) undoStack.shift(); redoStack = []; }
  function changed() {
    if (!editable || broken) return;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(flush, 250);
  }
  function flush() { clearTimeout(saveTimer); saveTimer = 0; if (editable && !broken) post({ type: 'save', json: JSON.stringify(doc) }); }
  function undo() { if (!undoStack.length) return; redoStack.push(snapshot()); doc = JSON.parse(undoStack.pop()); render(); changed(); }
  function redo() { if (!redoStack.length) return; undoStack.push(snapshot()); doc = JSON.parse(redoStack.pop()); render(); changed(); }

  function addNode(n, opts) {
    checkpoint();
    n = Object.assign({ id: newId() }, n);
    nodes().push(n);
    (n.type === 'group' ? groupsEl : nodesEl).appendChild(renderNode(n));
    if (n.type === 'group') groupsEl.prepend(nodeEl(n.id));   // groups sit under everything
    selN.clear(); selE.clear(); selN.add(n.id); refreshSelection();
    changed();
    if (opts && opts.edit && n.type === 'text') startEditing(n.id, true);
    return n;
  }
  function addText(x, y, edit) { return addNode({ type: 'text', text: '', x: Math.round(x - 125), y: Math.round(y - 30), width: 250, height: 60 }, { edit }); }
  function addFile(file, x, y) {
    const n = addNode({ type: 'file', file, x: Math.round(x - 200), y: Math.round(y - 200), width: 400, height: 400 });
    if (!fileInfo(n)) post({ type: 'needFiles', files: [{ file, subpath: '' }] });
    return n;
  }
  function addGroup(x, y) {
    const sel = nodes().filter(n => selN.has(n.id));
    const b = bounds(sel);
    const g = b ? { x: b.x - 30, y: b.y - 50, width: b.w + 60, height: b.h + 80 } : { x: Math.round(x - 200), y: Math.round(y - 150), width: 400, height: 300 };
    checkpoint();
    const n = Object.assign({ id: newId(), type: 'group' }, g, { label: '' });
    // groups go first so they're drawn (and saved) beneath their cards, as Obsidian does
    nodes().unshift(n);
    render(); selN.clear(); selE.clear(); selN.add(n.id); refreshSelection(); changed();
    renameGroup(n.id);
    return n;
  }
  function connect(from, fromSide, to, toSide) {
    checkpoint();
    const e = { id: newId(), fromNode: from, fromSide, toNode: to, toSide };
    edges().push(e);
    selN.clear(); selE.clear(); selE.add(e.id); refreshSelection(); changed();
    return e;
  }
  function deleteSelection() {
    if (!selN.size && !selE.size) return;
    checkpoint();
    doc.nodes = nodes().filter(n => !selN.has(n.id));
    doc.edges = edges().filter(e => !selE.has(e.id) && !selN.has(e.fromNode) && !selN.has(e.toNode));
    selN.clear(); selE.clear();
    render(); changed();
  }
  function setColor(color) {
    if (!selN.size && !selE.size) return;
    checkpoint();
    for (const n of nodes()) if (selN.has(n.id)) { if (color) n.color = color; else delete n.color; rerenderNode(n); }
    for (const e of edges()) if (selE.has(e.id)) { if (color) e.color = color; else delete e.color; }
    refreshSelection(); changed();
  }

  // MARK: text editing

  function startEditing(id, fresh) {
    if (!editable) return;
    const n = byId(id), el = nodeEl(id);
    if (!n || n.type !== 'text' || !el) return;
    if (editing) stopEditing(true);
    const ta = document.createElement('textarea');
    ta.className = 'editor'; ta.value = n.text || ''; ta.spellcheck = true;
    const body = el.querySelector('.body'); if (body) body.style.visibility = 'hidden';
    el.appendChild(ta); el.classList.add('editing');
    editing = { id, ta, before: snapshot(), fresh };
    ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length);
    ta.addEventListener('keydown', (ev) => {
      if (ev.key === 'Escape' || (ev.key === 'Enter' && ev.metaKey)) { ev.preventDefault(); ev.stopPropagation(); stopEditing(true); }
      ev.stopPropagation();
    });
    ta.addEventListener('blur', () => { if (editing && editing.ta === ta) stopEditing(true); });
  }
  function stopEditing(commit, quiet) {
    const ed = editing; if (!ed) return;
    editing = null;
    const n = byId(ed.id);
    if (n && commit && ed.ta.value !== (n.text || '')) {
      undoStack.push(ed.before); redoStack = [];
      n.text = ed.ta.value;
      changed();
    }
    if (!quiet && n) rerenderNode(n);
  }

  function renameGroup(id) {
    const n = byId(id), el = nodeEl(id); if (!n || !el || !editable) return;
    const lab = el.querySelector('.group-label');
    const inp = document.createElement('input');
    inp.value = n.label || ''; inp.placeholder = 'Group';
    inp.style.cssText = 'font: inherit; color: inherit; background: var(--background-primary); border: 0; outline: 1px solid var(--accent); border-radius: 3px; width: 14em;';
    lab.textContent = ''; lab.appendChild(inp); inp.focus(); inp.select();
    const done = (save) => {
      if (!inp.isConnected) return;
      if (save && inp.value !== (n.label || '')) { checkpoint(); n.label = inp.value; changed(); }
      rerenderNode(n); refreshSelection();
    };
    inp.addEventListener('keydown', (ev) => { ev.stopPropagation(); if (ev.key === 'Enter') done(true); if (ev.key === 'Escape') done(false); });
    inp.addEventListener('blur', () => done(true));
  }
  function editEdgeLabel(id) {
    const e = edges().find(x => x.id === id); if (!e || !editable) return;
    const g = edgeGeom(e); if (!g) return;
    let l = labelsEl.querySelector(`.edge-label[data-edge="${CSS.escape(id)}"]`);
    if (!l) { l = document.createElement('div'); l.className = 'edge-label'; l.style.left = g.mid[0] + 'px'; l.style.top = g.mid[1] + 'px'; labelsEl.appendChild(l); }
    const inp = document.createElement('input'); inp.value = e.label || ''; inp.placeholder = 'label';
    l.textContent = ''; l.appendChild(inp); inp.focus(); inp.select();
    const done = (save) => {
      if (!inp.isConnected) return;
      if (save && inp.value !== (e.label || '')) { checkpoint(); if (inp.value) e.label = inp.value; else delete e.label; changed(); }
      drawEdges();
    };
    inp.addEventListener('keydown', (ev) => { ev.stopPropagation(); if (ev.key === 'Enter') done(true); if (ev.key === 'Escape') done(false); });
    inp.addEventListener('blur', () => done(true));
  }

  // MARK: pointer

  const inChrome = (t) => t.closest && (t.closest('#menu') || t.closest('#picker') || t.closest('#controls'));
  function containedIn(g) {
    const G = box(g);
    return nodes().filter(n => n !== g && (() => { const b = box(n); return b.x >= G.x && b.y >= G.y && b.x + b.w <= G.x + G.w && b.y + b.h <= G.y + G.h; })());
  }
  function sideAt(n, wx, wy) {
    let best = 'top', bd = Infinity;
    for (const s of ['top', 'right', 'bottom', 'left']) { const p = sidePoint(n, s), d = Math.hypot(p[0] - wx, p[1] - wy); if (d < bd) { bd = d; best = s; } }
    return best;
  }

  stage.addEventListener('pointerdown', (ev) => {
    hideMenu();
    if (ev.button !== 0) return;
    const t = ev.target;
    if (editing && t.closest('textarea.editor')) return;
    if (t.closest('input')) return;
    if (editing) stopEditing(true);
    const w = toWorld(ev.clientX, ev.clientY);
    const nEl = t.closest('.node'), side = t.closest('.h-side'), rz = t.closest('.h-resize');
    const edgeId = (t.dataset && t.dataset.edge) || (t.closest('.edge-label') && t.closest('.edge-label').dataset.edge);
    const start = { cx: ev.clientX, cy: ev.clientY, w, moved: false };
    if (editable && side && nEl) {
      const n = byId(nEl.dataset.id);
      mode = { kind: 'connect', from: n, side: side.dataset.side, ...start };
      document.body.classList.add('connecting');
    } else if (editable && rz && nEl) {
      const n = byId(nEl.dataset.id);
      if (!selN.has(n.id)) { selN.clear(); selE.clear(); selN.add(n.id); refreshSelection(); }
      mode = { kind: 'resize', n, dir: rz.dataset.dir, b0: box(n), before: snapshot(), ...start };
    } else if (nEl) {
      const id = nEl.dataset.id;
      if (ev.shiftKey) { selN.has(id) ? selN.delete(id) : selN.add(id); }
      else if (!selN.has(id)) { selN.clear(); selE.clear(); selN.add(id); }
      refreshSelection();
      // a click on a link inside a card shouldn't start a drag
      if (t.closest('a')) return;
      const moving = new Set();
      for (const s of selN) { const n = byId(s); if (!n) continue; moving.add(n); if (n.type === 'group') containedIn(n).forEach(m => moving.add(m)); }
      mode = { kind: 'move', nodes: [...moving].map(n => ({ n, x: box(n).x, y: box(n).y })), before: snapshot(), ...start };
    } else if (edgeId) {
      if (ev.shiftKey) { selE.has(edgeId) ? selE.delete(edgeId) : selE.add(edgeId); } else { selN.clear(); selE.clear(); selE.add(edgeId); }
      refreshSelection();
      return;
    } else if (ev.shiftKey) {
      mode = { kind: 'marquee', ...start };
    } else {
      mode = { kind: 'pan', cam0: { ...cam }, ...start };
    }
    ev.preventDefault();   // no text selection or focus change while dragging
  });

  // window-level (not pointer capture) so click and dblclick still land on the card
  window.addEventListener('pointermove', (ev) => {
    lastWorldPoint = toWorld(ev.clientX, ev.clientY);
    if (!mode) return;
    const dx = ev.clientX - mode.cx, dy = ev.clientY - mode.cy;
    if (!mode.moved && Math.hypot(dx, dy) < 3) return;
    mode.moved = true;
    const wdx = dx / cam.z, wdy = dy / cam.z;
    switch (mode.kind) {
      case 'pan':
        stage.classList.add('panning');
        cam.x = mode.cam0.x + dx; cam.y = mode.cam0.y + dy; applyCam(); break;
      case 'move':
        if (!editable) break;
        for (const m of mode.nodes) { m.n.x = Math.round(m.x + wdx); m.n.y = Math.round(m.y + wdy); layoutNode(m.n); }
        drawEdges(); break;
      case 'resize': {
        const b = mode.b0, d = mode.dir, n = mode.n, min = 40;
        let x = b.x, y = b.y, w = b.w, h = b.h;
        if (d.includes('e')) w = Math.max(min, b.w + wdx);
        if (d.includes('s')) h = Math.max(min, b.h + wdy);
        if (d.includes('w')) { w = Math.max(min, b.w - wdx); x = b.x + b.w - w; }
        if (d.includes('n')) { h = Math.max(min, b.h - wdy); y = b.y + b.h - h; }
        n.x = Math.round(x); n.y = Math.round(y); n.width = Math.round(w); n.height = Math.round(h);
        layoutNode(n); drawEdges(); break;
      }
      case 'connect': {
        const p1 = sidePoint(mode.from, mode.side), w = toWorld(ev.clientX, ev.clientY);
        const over = document.elementFromPoint(ev.clientX, ev.clientY), oEl = over && over.closest('.node');
        const target = oEl && oEl.dataset.id !== mode.from.id ? byId(oEl.dataset.id) : null;
        if (target && target.type !== 'group') { const s = sideAt(target, w.x, w.y); drawEdges({ p1, s1: mode.side, p2: sidePoint(target, s), s2: s }); }
        else drawEdges({ p1, s1: mode.side, p2: [w.x, w.y] });
        break;
      }
      case 'marquee': {
        const x = Math.min(ev.clientX, mode.cx), y = Math.min(ev.clientY, mode.cy);
        marquee.hidden = false;
        Object.assign(marquee.style, { left: x + 'px', top: y + 'px', width: Math.abs(dx) + 'px', height: Math.abs(dy) + 'px' });
        const a = toWorld(x, y), b = toWorld(x + Math.abs(dx), y + Math.abs(dy));
        selN.clear(); selE.clear();
        for (const n of nodes()) { const B = box(n); if (B.x >= a.x && B.y >= a.y && B.x + B.w <= b.x && B.y + B.h <= b.y) selN.add(n.id); }
        refreshSelection(); break;
      }
    }
  });

  window.addEventListener('pointerup', (ev) => {
    const m = mode; mode = null;
    stage.classList.remove('panning'); document.body.classList.remove('connecting');
    marquee.hidden = true;
    if (!m) return;
    if (!m.moved) {
      if (m.kind === 'pan') { if (selN.size || selE.size) { selN.clear(); selE.clear(); refreshSelection(); } }
      if (m.kind === 'connect') drawEdges();
      return;
    }
    if ((m.kind === 'move' || m.kind === 'resize') && editable) { undoStack.push(m.before); redoStack = []; changed(); }
    if (m.kind === 'connect') {
      const w = toWorld(ev.clientX, ev.clientY);
      const over = document.elementFromPoint(ev.clientX, ev.clientY), oEl = over && over.closest('.node');
      const target = oEl && oEl.dataset.id !== m.from.id ? byId(oEl.dataset.id) : null;
      if (target && target.type !== 'group') connect(m.from.id, m.side, target.id, sideAt(target, w.x, w.y));
      else {
        // dropped on empty space: a new card there, connected, ready to type (as Obsidian)
        const n = NORMAL[m.side];
        const card = addText(w.x + n[0] * 125, w.y + n[1] * 30, false);
        const opposite = { top: 'bottom', bottom: 'top', left: 'right', right: 'left' }[m.side];
        undoStack.pop();   // one undo step for card + edge
        edges().push({ id: newId(), fromNode: m.from.id, fromSide: m.side, toNode: card.id, toSide: opposite });
        drawEdges(); changed();
        startEditing(card.id, true);
      }
    }
  });

  stage.addEventListener('dblclick', (ev) => {
    if (inChrome(ev.target) || ev.target.closest('textarea') || ev.target.closest('input')) return;
    const nEl = ev.target.closest('.node');
    const edgeId = (ev.target.dataset && ev.target.dataset.edge) || (ev.target.closest('.edge-label') && ev.target.closest('.edge-label').dataset.edge);
    if (edgeId) { editEdgeLabel(edgeId); return; }
    if (nEl) {
      const n = byId(nEl.dataset.id); if (!n) return;
      if (n.type === 'text') startEditing(n.id);
      else if (n.type === 'file') { const f = fileInfo(n); post({ type: 'openFile', path: (f && f.path) || n.file }); }
      else if (n.type === 'link' && n.url) post({ type: 'url', url: n.url });
      else if (n.type === 'group') { if (ev.target.closest('.group-label')) renameGroup(n.id); else if (editable) { const w = toWorld(ev.clientX, ev.clientY); addText(w.x, w.y, true); } }
      return;
    }
    if (!editable) return;
    const w = toWorld(ev.clientX, ev.clientY);
    addText(w.x, w.y, true);
  });

  // trackpad: two-finger scroll pans, pinch (ctrl-wheel) zooms; ⌘-scroll zooms a mouse wheel
  stage.addEventListener('wheel', (ev) => {
    if (inChrome(ev.target)) return;
    if (!ev.ctrlKey && !ev.metaKey) {
      const body = ev.target.closest('.node.selected > .body, .node.editing textarea');
      if (body) {
        const canY = ev.deltaY < 0 ? body.scrollTop > 0 : body.scrollTop + body.clientHeight < body.scrollHeight - 1;
        if (Math.abs(ev.deltaY) >= Math.abs(ev.deltaX) && canY) return;   // scroll inside the card
      }
      ev.preventDefault();
      cam.x -= ev.deltaX; cam.y -= ev.deltaY; applyCam();
      return;
    }
    ev.preventDefault();
    const k = ev.ctrlKey ? 0.011 : 0.0025;
    zoomAt(ev.clientX, ev.clientY, Math.exp(-ev.deltaY * k));
  }, { passive: false });
  // Safari's own pinch gestures would zoom the page
  for (const g of ['gesturestart', 'gesturechange', 'gestureend']) document.addEventListener(g, (e) => e.preventDefault());

  // MARK: keys

  document.addEventListener('keydown', (ev) => {
    if (ev.target.closest && (ev.target.closest('input') || ev.target.closest('textarea'))) return;
    if (!picker.hidden) return;
    const mod = ev.metaKey || ev.ctrlKey;
    if (mod && ev.key.toLowerCase() === 'z') { ev.preventDefault(); if (!editable) return; ev.shiftKey ? redo() : undo(); return; }
    if (mod && ev.key.toLowerCase() === 'y') { ev.preventDefault(); if (editable) redo(); return; }
    if (mod && ev.key.toLowerCase() === 'a') { ev.preventDefault(); nodes().forEach(n => selN.add(n.id)); refreshSelection(); return; }
    if (mod) return;
    if (ev.key === '!' || (ev.shiftKey && ev.code === 'Digit1')) { ev.preventDefault(); fit(null, true); return; }
    if (ev.key === '@' || (ev.shiftKey && ev.code === 'Digit2')) { ev.preventDefault(); const s = nodes().filter(n => selN.has(n.id)); fit(s.length ? s : null, true); return; }
    if (!editable) return;
    if (ev.key === 'Backspace' || ev.key === 'Delete') { ev.preventDefault(); deleteSelection(); return; }
    if (ev.key === 'Enter' && selN.size === 1) { const n = byId([...selN][0]); if (n && n.type === 'text') { ev.preventDefault(); startEditing(n.id); } return; }
    if (ev.key === 'Escape' && (selN.size || selE.size)) { selN.clear(); selE.clear(); refreshSelection(); return; }
    const arrows = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
    if (arrows[ev.key] && selN.size) {
      ev.preventDefault();
      const step = ev.shiftKey ? 20 : 2, [ax, ay] = arrows[ev.key];
      checkpoint();
      for (const n of nodes()) if (selN.has(n.id)) { n.x = num(n.x, 0) + ax * step; n.y = num(n.y, 0) + ay * step; layoutNode(n); }
      drawEdges(); changed();
    }
  });

  // MARK: menus

  function hideMenu() { menu.hidden = true; menu.textContent = ''; }
  function showMenu(x, y, items) {
    menu.textContent = '';
    for (const it of items) {
      if (it === '-') { menu.appendChild(document.createElement('hr')); continue; }
      if (it.swatches) {
        const row = document.createElement('div'); row.className = 'swatches';
        for (const c of [null, '1', '2', '3', '4', '5', '6']) {
          const s = document.createElement('span'); s.className = 'swatch' + (c ? '' : ' none') + ((it.current || null) === c ? ' on' : '');
          if (c) s.style.background = `rgb(${PRESETS[c].join(',')})`;
          s.title = c ? ['red', 'orange', 'yellow', 'green', 'cyan', 'purple'][+c - 1] : 'no color';
          s.addEventListener('click', () => { hideMenu(); setColor(c); });
          row.appendChild(s);
        }
        menu.appendChild(row); continue;
      }
      const b = document.createElement('button');
      b.innerHTML = `<span>${esc(it.title)}</span>${it.key ? `<span class="k">${esc(it.key)}</span>` : ''}`;
      b.addEventListener('click', () => { hideMenu(); it.run(); });
      menu.appendChild(b);
    }
    menu.hidden = false;
    const r = menu.getBoundingClientRect();
    menu.style.left = Math.min(x, window.innerWidth - r.width - 6) + 'px';
    menu.style.top = Math.min(y, window.innerHeight - r.height - 6) + 'px';
  }
  document.addEventListener('contextmenu', (ev) => {
    ev.preventDefault();
    if (inChrome(ev.target)) return;
    if (editing) stopEditing(true);
    const w = toWorld(ev.clientX, ev.clientY);
    const nEl = ev.target.closest('.node');
    const edgeId = (ev.target.dataset && ev.target.dataset.edge) || (ev.target.closest('.edge-label') && ev.target.closest('.edge-label').dataset.edge);
    if (nEl) {
      const n = byId(nEl.dataset.id);
      if (!selN.has(n.id)) { selN.clear(); selE.clear(); selN.add(n.id); refreshSelection(); }
      const items = [];
      if (n.type === 'file') items.push({ title: 'Open', key: 'double-click', run: () => { const f = fileInfo(n); post({ type: 'openFile', path: (f && f.path) || n.file }); } });
      if (n.type === 'link') items.push({ title: 'Open link', run: () => post({ type: 'url', url: n.url }) });
      if (editable) {
        if (n.type === 'text' && selN.size === 1) items.push({ title: 'Edit', key: '↩', run: () => startEditing(n.id) });
        if (n.type === 'group') items.push({ title: 'Rename group', run: () => renameGroup(n.id) });
        if (items.length) items.push('-');
        items.push({ swatches: true, current: selN.size === 1 ? (n.color || null) : undefined });
        items.push({ title: 'Group selection', run: () => addGroup(w.x, w.y) });
        items.push('-');
        items.push({ title: selN.size > 1 ? `Delete ${selN.size} cards` : 'Delete', key: '⌫', run: deleteSelection });
      }
      if (items.length) showMenu(ev.clientX, ev.clientY, items);
      return;
    }
    if (edgeId) {
      const e = edges().find(x => x.id === edgeId);
      if (!selE.has(edgeId)) { selN.clear(); selE.clear(); selE.add(edgeId); refreshSelection(); }
      if (!editable || !e) return;
      showMenu(ev.clientX, ev.clientY, [
        { swatches: true, current: e.color || null },
        { title: e.label ? 'Edit label' : 'Add label', run: () => editEdgeLabel(e.id) },
        { title: (e.fromEnd === 'arrow' ? '✓ ' : '') + 'Arrow at start', run: () => { checkpoint(); if (e.fromEnd === 'arrow') delete e.fromEnd; else e.fromEnd = 'arrow'; drawEdges(); changed(); } },
        { title: ((e.toEnd || 'arrow') !== 'none' ? '✓ ' : '') + 'Arrow at end', run: () => { checkpoint(); if ((e.toEnd || 'arrow') !== 'none') e.toEnd = 'none'; else delete e.toEnd; drawEdges(); changed(); } },
        '-',
        { title: 'Delete', key: '⌫', run: deleteSelection },
      ]);
      return;
    }
    const items = [];
    if (editable) {
      items.push({ title: 'Add card', key: 'double-click', run: () => addText(w.x, w.y, true) });
      items.push({ title: 'Add note…', run: () => openPicker(w) });
      items.push({ title: selN.size ? 'Group selection' : 'Add group', run: () => addGroup(w.x, w.y) });
      items.push('-');
    }
    items.push({ title: 'Zoom to fit', key: '⇧1', run: () => fit(null, true) });
    if (editable) {
      items.push('-');
      items.push({ title: 'Undo', key: '⌘Z', run: undo });
      items.push({ title: 'Redo', key: '⇧⌘Z', run: redo });
    }
    showMenu(ev.clientX, ev.clientY, items);
  });
  document.addEventListener('pointerdown', (ev) => { if (!inChrome(ev.target)) hideMenu(); if (!picker.hidden && !ev.target.closest('#picker')) closePicker(); }, true);

  $('controls').addEventListener('click', (ev) => {
    const b = ev.target.closest('button'); if (!b) return;
    const W = window.innerWidth / 2, H = window.innerHeight / 2;
    if (b.dataset.act === 'zoomIn') zoomAt(W, H, 1.25);
    if (b.dataset.act === 'zoomOut') zoomAt(W, H, 0.8);
    if (b.dataset.act === 'fit') fit(null, true);
  });

  // note picker (rows come from Swift's ⌘O matcher)
  let pickAt = null, pickRows = [], pickSel = 0, pickId = 0;
  function openPicker(w) {
    pickAt = w || toWorld(window.innerWidth / 2, window.innerHeight / 2);
    picker.hidden = false; pickQ.value = ''; pickRows = []; pickList.textContent = '';
    pickQ.focus(); post({ type: 'search', q: '', id: ++pickId });
  }
  function closePicker() { picker.hidden = true; pickQ.blur(); }
  function drawPick() {
    pickList.innerHTML = pickRows.map((r, i) => `<div class="row${i === pickSel ? ' on' : ''}" data-i="${i}">${esc(r.name)}<div class="f">${esc(r.folder || '/')}</div></div>`).join('');
  }
  function choose(i) {
    const r = pickRows[i]; if (!r) return;
    closePicker(); addFile(r.path, pickAt.x, pickAt.y);
  }
  pickQ.addEventListener('input', () => post({ type: 'search', q: pickQ.value, id: ++pickId }));
  pickQ.addEventListener('keydown', (ev) => {
    ev.stopPropagation();
    if (ev.key === 'Escape') { ev.preventDefault(); closePicker(); }
    else if (ev.key === 'ArrowDown') { ev.preventDefault(); pickSel = Math.min(pickRows.length - 1, pickSel + 1); drawPick(); }
    else if (ev.key === 'ArrowUp') { ev.preventDefault(); pickSel = Math.max(0, pickSel - 1); drawPick(); }
    else if (ev.key === 'Enter') { ev.preventDefault(); choose(pickSel); }
  });
  pickList.addEventListener('click', (ev) => { const r = ev.target.closest('.row'); if (r) choose(+r.dataset.i); });

  function flashHint(text) { hint.textContent = text; hint.classList.add('on'); clearTimeout(flashHint.t); flashHint.t = setTimeout(() => hint.classList.remove('on'), 2600); }

  // MARK: Swift → page

  Object.assign(window.Onyx, {
    canvasLoad(payload) {
      const keep = payload.keepView && path === payload.path;
      P = { files: payload.files || {}, links: payload.links || {}, embeds: payload.embeds || {}, base: payload.base || '' };
      path = payload.path;
      document.body.classList.toggle('theme-dark', !!payload.dark);
      document.body.classList.toggle('theme-light', !payload.dark);
      document.documentElement.classList.toggle('dark', !!payload.dark);
      const old = $('error'); if (old) old.remove();
      broken = false;
      try {
        const text = (payload.json || '').trim();
        doc = text ? JSON.parse(text) : { nodes: [], edges: [] };
        if (!doc || typeof doc !== 'object' || Array.isArray(doc)) throw new Error('not a canvas');
      } catch (e) {
        // never write back over a file we couldn't read
        broken = true; doc = { nodes: [], edges: [] };
        const d = document.createElement('div'); d.id = 'error'; d.textContent = 'This canvas couldn’t be read (' + e.message + '). Nothing will be changed.';
        document.body.appendChild(d);
      }
      if (!keep) { undoStack = []; redoStack = []; selN.clear(); selE.clear(); }
      editable = payload.editable !== false && !broken;
      document.body.classList.toggle('editable', editable);
      render();
      if (!keep) { fit(null, false); if (!nodes().length && editable) flashHint('Double-click to add a card · right-click for more'); }
      else applyCam();
    },
    canvasRefresh(r) {
      Object.assign(P, { files: r.files || P.files, links: r.links || P.links, embeds: r.embeds || P.embeds, base: r.base || P.base });
      for (const n of nodes()) if ((n.type === 'file' || n.type === 'text') && !(editing && editing.id === n.id)) { const el = nodeEl(n.id); if (el) rerenderNode(n); }
      refreshSelection();
    },
    canvasFiles(files) {
      Object.assign(P.files, files || {});
      for (const n of nodes()) if (n.type === 'file') rerenderNode(n);
      refreshSelection();
    },
    canvasPickResults(id, rows) {
      if (id !== pickId) return;
      pickRows = rows || []; pickSel = 0; drawPick();
    },
    canvasSetEditable(on) {
      editable = !!on && !broken;
      document.body.classList.toggle('editable', editable);
      if (!editable && editing) stopEditing(true);
    },
    // test hooks (scripted checks through the app's `js` command)
    _canvas: {
      state() { return JSON.stringify({ path, nodes: nodes().length, edges: edges().length, sel: [...selN, ...selE], cam, undo: undoStack.length, editable, broken }); },
      doc() { return JSON.stringify(doc); },
      addText(x, y, text) { const n = addText(x, y, false); if (text != null) { n.text = text; rerenderNode(n); changed(); } return n.id; },
      addFile(file, x, y) { return addFile(file, x, y).id; },
      move(id, dx, dy) { const n = byId(id); checkpoint(); n.x += dx; n.y += dy; layoutNode(n); drawEdges(); changed(); },
      resize(id, w, h) { const n = byId(id); checkpoint(); n.width = w; n.height = h; layoutNode(n); drawEdges(); changed(); },
      connect(a, as, b, bs) { return connect(a, as, b, bs).id; },
      select(ids) { selN.clear(); selE.clear(); for (const i of ids) (byId(i) ? selN : selE).add(i); refreshSelection(); },
      del() { deleteSelection(); },
      color(c) { setColor(c); },
      group() { return addGroup(0, 0).id; },
      undo, redo, flush, fit: () => fit(null, false),
      zoom(f) { zoomAt(window.innerWidth / 2, window.innerHeight / 2, f); return cam.z; },
      pan(dx, dy) { cam.x += dx; cam.y += dy; applyCam(); return JSON.stringify(cam); },
      dom() { return JSON.stringify({ cards: nodesEl.children.length, groups: groupsEl.children.length, edges: edgesEl.querySelectorAll('g.edge').length, labels: labelsEl.children.length, notes: nodesEl.querySelectorAll('.canvas-md').length, missing: document.querySelectorAll('.missing').length }); },
    },
  });

  window.addEventListener('resize', () => drawEdges());
  applyCam();
})();
