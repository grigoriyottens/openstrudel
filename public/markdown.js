/* Message text for the web transcript.
 * A small Markdown reader that runs in linear time and builds DOM nodes only:
 * raw HTML stays text, only absolute https, http and mailto links survive, and
 * images become links so a reply never loads a remote file. It also finds where
 * the transcript starts a new time cluster. */
(function (root) {
  const LIMIT = 100000;
  const MAX_DEPTH = 12;
  const CLUSTER_GAP = 30 * 60 * 1000;
  const PUNCTUATION = /[!-/:-@[-`{-~¡-¿‐-‧‰-⁞　-〿]/;
  const SPACE = /\s/;
  const OBJECT = '￼';

  function safeHref(raw) {
    if (typeof raw !== 'string') return null;
    const value = raw.trim();
    if (!/^(?:https?|mailto):/i.test(value)) return null;
    let url;
    try { url = new URL(value); } catch { return null; }
    if (url.protocol === 'mailto:') return url.pathname ? url.href : null;
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
    if (!url.hostname || url.username || url.password) return null;
    return url.href;
  }

  // ---------- Inline ----------

  /* Pass 1 resolves backslash escapes, code spans and <autolinks> into a working
   * string. A code span or autolink becomes one object character, so nothing inside
   * it can act as syntax. `literal` marks characters that never act as syntax. */
  function prepare(source) {
    const n = source.length;
    const runAt = new Map();
    const runs = [];
    for (let i = 0; i < n;) {
      if (source[i] !== '`') { i++; continue; }
      let j = i; while (j < n && source[j] === '`') j++;
      runAt.set(i, runs.length); runs.push({ start: i, length: j - i, next: -1 });
      i = j;
    }
    const lastByLength = new Map();
    for (let r = runs.length - 1; r >= 0; r--) {
      runs[r].next = lastByLength.has(runs[r].length) ? lastByLength.get(runs[r].length) : -1;
      lastByLength.set(runs[r].length, r);
    }
    const out = [], literal = [], objects = new Map();
    const push = (text, isLiteral) => { for (let k = 0; k < text.length; k++) { out.push(text[k]); literal.push(isLiteral ? 1 : 0); } };
    for (let i = 0; i < n;) {
      const ch = source[i];
      if (ch === '\\' && source[i + 1] === '\n') { i++; continue; }
      if (ch === '\\' && i + 1 < n && /[!-/:-@[-`{-~]/.test(source[i + 1])) { out.push(source[i + 1]); literal.push(1); i += 2; continue; }
      if (ch === '`') {
        const r = runAt.get(i);
        if (r === undefined) { out.push(ch); literal.push(1); i++; continue; }
        const run = runs[r];
        if (run.next < 0) { push(source.slice(i, i + run.length), true); i += run.length; continue; }
        const close = runs[run.next];
        let text = source.slice(i + run.length, close.start).replace(/\n/g, ' ');
        if (text.length > 2 && text[0] === ' ' && text[text.length - 1] === ' ' && text.trim()) text = text.slice(1, -1);
        objects.set(out.length, { type: 'code', text });
        out.push(OBJECT); literal.push(1);
        i = close.start + close.length;
        continue;
      }
      if (ch === '<' && (source.startsWith('http', i + 1) || source.startsWith('mailto:', i + 1))) {
        let j = i + 1;
        while (j < n && source[j] !== '>' && source[j] !== '<' && !SPACE.test(source[j])) j++;
        const href = j < n && source[j] === '>' ? safeHref(source.slice(i + 1, j)) : null;
        if (href) {
          objects.set(out.length, { type: 'link', href, children: [{ type: 'text', text: source.slice(i + 1, j) }] });
          out.push(OBJECT); literal.push(1);
          i = j + 1;
          continue;
        }
      }
      out.push(ch); literal.push(0); i++;
    }
    return { text: out.join(''), literal: Uint8Array.from(literal), objects };
  }

  /* Pass 2 precomputes every lookup the main loop needs, so each opener finds its
   * closer in constant time: bracket pairs, parenthesis pairs (a destination has no
   * spaces), the next space, and delimiter runs with their next possible closer. */
  function index(prepared) {
    const { text, literal } = prepared, n = text.length;
    const bracket = new Int32Array(n).fill(-1), paren = new Int32Array(n).fill(-1), nextSpace = new Int32Array(n + 1);
    const brackets = [], parens = [];
    for (let i = 0; i < n; i++) {
      const ch = text[i];
      if (literal[i]) continue;
      if (ch === '[') brackets.push(i);
      else if (ch === ']' && brackets.length) bracket[brackets.pop()] = i;
      if (ch === '(') parens.push(i);
      else if (ch === ')' && parens.length) paren[parens.pop()] = i;
      else if (SPACE.test(ch)) parens.length = 0;
    }
    nextSpace[n] = n;
    for (let i = n - 1; i >= 0; i--) nextSpace[i] = SPACE.test(text[i]) ? i : nextSpace[i + 1];
    const runOf = new Int32Array(n).fill(-1), runs = [];
    for (let i = 0; i < n;) {
      const ch = text[i];
      if ((ch !== '*' && ch !== '_' && ch !== '~') || literal[i]) { i++; continue; }
      let j = i; while (j < n && text[j] === ch && !literal[j]) j++;
      const before = i > 0 ? text[i - 1] : ' ', after = j < n ? text[j] : ' ';
      const beforeSpace = SPACE.test(before), afterSpace = SPACE.test(after);
      const beforePunct = PUNCTUATION.test(before), afterPunct = PUNCTUATION.test(after);
      const left = !afterSpace && (!afterPunct || beforeSpace || beforePunct);
      const right = !beforeSpace && (!beforePunct || afterSpace || afterPunct);
      let open = left, close = right;
      if (ch === '_') { open = left && (!right || beforePunct); close = right && (!left || afterPunct); }
      if (ch === '~' && j - i !== 2) open = close = false;
      for (let k = i; k < j; k++) runOf[k] = runs.length;
      runs.push({ ch, start: i, end: j, open, close, next1: -1, next2: -1 });
      i = j;
    }
    for (const ch of ['*', '_', '~']) {
      let one = -1, two = -1;
      for (let r = runs.length - 1; r >= 0; r--) {
        if (runs[r].ch !== ch) continue;
        runs[r].next1 = one; runs[r].next2 = two;
        if (runs[r].close) { one = r; if (runs[r].end - runs[r].start >= 2) two = r; }
      }
    }
    return { ...prepared, bracket, paren, nextSpace, runOf, runs };
  }

  function parseInline(source) {
    const doc = index(prepare(source));
    return inline(doc, 0, doc.text.length, 0, false);
  }

  function inline(doc, start, end, depth, insideLink) {
    const { text, literal, objects, bracket, paren, nextSpace, runOf, runs } = doc;
    const nodes = [];
    let buffer = '';
    const flush = () => { if (buffer) { nodes.push({ type: 'text', text: buffer }); buffer = ''; } };
    const node = (value) => { flush(); nodes.push(value); };
    let i = start;
    while (i < end) {
      const ch = text[i];
      if (ch === OBJECT && objects.has(i)) {
        const object = objects.get(i);
        if (object.type === 'link' && insideLink) buffer += object.children[0].text;
        else node(object);
        i++; continue;
      }
      if (ch === '\n') {
        buffer = buffer.replace(/[ \t]+$/, '');
        node({ type: 'break' });
        i++; while (i < end && (text[i] === ' ' || text[i] === '\t')) i++;
        continue;
      }
      if (!literal[i] && depth < MAX_DEPTH && (ch === '[' || (ch === '!' && text[i + 1] === '[' && !literal[i + 1]))) {
        const open = ch === '!' ? i + 1 : i, close = bracket[open];
        const link = close > open && close < end ? destination(doc, close + 1, end) : null;
        if (link) {
          const label = inline(doc, open + 1, close, depth + 1, true);
          const href = insideLink ? null : safeHref(link.href);
          if (href) {
            const children = ch === '!' && !plain(label) ? [{ type: 'text', text: link.href }] : label;
            node({ type: 'link', href, children });
          } else { flush(); nodes.push(...label); }
          i = link.end;
          continue;
        }
      }
      if (!insideLink && ch === 'h' && (text.startsWith('https://', i) || text.startsWith('http://', i)) && (i === 0 || !/[\p{L}\p{N}]/u.test(text[i - 1]))) {
        let j = Math.min(nextSpace[i], end);
        let k = i; while (k < j && text[k] !== '<' && text[k] !== '>' && text[k] !== OBJECT) k++;
        j = trimURL(text, i, k);
        const href = j > i ? safeHref(text.slice(i, j)) : null;
        if (href) { node({ type: 'link', href, children: [{ type: 'text', text: text.slice(i, j) }] }); i = j; continue; }
        buffer += text.slice(i, k); i = k; continue;
      }
      const r = runOf[i];
      if (r >= 0 && depth < MAX_DEPTH) {
        const run = runs[r], available = run.end - i;
        if (run.open) {
          const length = run.ch === '~' ? 2 : available >= 2 ? 2 : 1;
          const found = emphasis(runs, run, length, i + length, end);
          if (found) {
            const type = run.ch === '~' ? 'del' : length === 2 ? 'strong' : 'em';
            node({ type, children: inline(doc, i + length, found.from, depth + 1, insideLink) });
            i = found.to;
            continue;
          }
          if (length === 2 && run.ch !== '~') {
            const single = emphasis(runs, run, 1, i + 1, end);
            if (single) { node({ type: 'em', children: inline(doc, i + 1, single.from, depth + 1, insideLink) }); i = single.to; continue; }
          }
        }
        buffer += text.slice(i, run.end <= end ? run.end : end);
        i = Math.min(run.end, end);
        continue;
      }
      buffer += ch; i++;
    }
    flush();
    return nodes;
  }

  function emphasis(runs, run, length, after, end) {
    const index = length === 2 ? run.next2 : run.next1;
    if (index < 0) return null;
    const closer = runs[index];
    if (closer.start >= end) return null;
    const visibleEnd = Math.min(closer.end, end);
    if (visibleEnd - closer.start < length) return null;
    const from = visibleEnd - length;
    if (from <= after) return null;
    return { from, to: visibleEnd };
  }

  function destination(doc, at, end) {
    const { text, paren, nextSpace } = doc;
    if (text[at] !== '(') return null;
    const close = paren[at];
    if (close > at && close < end) return { href: text.slice(at + 1, close), end: close + 1 };
    let i = at + 1;
    while (i < end && (text[i] === ' ' || text[i] === '\t')) i++;
    const stop = Math.min(nextSpace[i], end);
    if (stop <= i) return null;
    const href = text.slice(i, stop);
    i = stop;
    while (i < end && (text[i] === ' ' || text[i] === '\t')) i++;
    if (text[i] === '"' || text[i] === "'") {
      const quote = text[i];
      let j = i + 1;
      const limit = Math.min(end, i + 1 + 512);
      while (j < limit && text[j] !== quote) j++;
      if (j >= limit) return null;
      i = j + 1;
      while (i < end && (text[i] === ' ' || text[i] === '\t')) i++;
    }
    return text[i] === ')' && i < end ? { href, end: i + 1 } : null;
  }

  /* Sentence punctuation after an address is not part of it; a closing parenthesis
   * is, when the address opened one. */
  function trimURL(text, start, end) {
    let open = 0, close = 0;
    for (let k = start; k < end; k++) { if (text[k] === '(') open++; else if (text[k] === ')') close++; }
    let j = end;
    while (j > start) {
      const last = text[j - 1];
      if ('.,:;!?\'"*_~'.includes(last)) { j--; continue; }
      if (last === ')' && close > open) { close--; j--; continue; }
      break;
    }
    return j;
  }

  function plain(nodes) { return nodes.map(n => n.type === 'text' ? n.text : n.children ? plain(n.children) : n.text || '').join(''); }

  // ---------- Blocks ----------

  const blank = line => !/\S/.test(line);
  function indentOf(line) { let i = 0; while (i < line.length && line[i] === ' ') i++; return i; }
  function fence(line) {
    const m = /^( {0,3})(`{3,}|~{3,})(.*)$/.exec(line);
    if (!m || (m[2][0] === '`' && m[3].includes('`'))) return null;
    return { indent: m[1].length, ch: m[2][0], length: m[2].length, info: m[3].trim() };
  }
  function heading(line) {
    const m = /^ {0,3}(#{1,6})(?=[ \t]|$)/.exec(line);
    if (!m) return null;
    let content = line.slice(m[0].length).trim();
    let j = content.length;
    while (j > 0 && content[j - 1] === '#') j--;
    if (j === 0) content = '';
    else if (j < content.length && (content[j - 1] === ' ' || content[j - 1] === '\t')) content = content.slice(0, j).trim();
    return { level: m[1].length, content };
  }
  function rule(line) { return indentOf(line) < 4 && /^(?:-{3,}|\*{3,}|_{3,})$/.test(line.replace(/[ \t]/g, '')); }
  function quote(line) { return /^ {0,3}>/.test(line); }
  function listItem(line) {
    const m = /^( *)([-*+]|(\d{1,9})([.)]))( +|\t|$)/.exec(line);
    if (!m) return null;
    const indent = m[1].length, marker = m[2], after = m[5];
    const content = line.slice(m[0].length);
    const spaces = after === '\t' ? 1 : after.length;
    const width = !content.trim() ? indent + marker.length + 1 : spaces > 4 ? indent + marker.length + 1 : indent + marker.length + spaces;
    return { indent, ordered: Boolean(m[3]), number: m[3] ? Number(m[3]) : 0, kind: m[3] ? m[4] : marker, width, content: spaces > 4 ? line.slice(indent + marker.length + 1) : content };
  }
  function cells(line) {
    let row = line.trim();
    if (row.startsWith('|')) row = row.slice(1);
    if (row.endsWith('|') && !row.endsWith('\\|')) row = row.slice(0, -1);
    const result = [];
    let current = '';
    for (let i = 0; i < row.length; i++) {
      if (row[i] === '\\' && row[i + 1] === '|') { current += '|'; i++; continue; }
      if (row[i] === '|') { result.push(current.trim()); current = ''; continue; }
      current += row[i];
    }
    result.push(current.trim());
    return result;
  }
  function delimiterRow(line) {
    if (!line || !line.includes('-') || indentOf(line) > 3) return null;
    const parts = cells(line);
    const align = [];
    for (const part of parts) {
      if (!/^:?-+:?$/.test(part)) return null;
      align.push(part.startsWith(':') && part.endsWith(':') ? 'center' : part.endsWith(':') ? 'right' : part.startsWith(':') ? 'left' : null);
    }
    return align;
  }
  function tableStart(lines, i) {
    if (!lines[i].includes('|') || i + 1 >= lines.length) return null;
    const align = delimiterRow(lines[i + 1]);
    return align && cells(lines[i]).length === align.length ? align : null;
  }
  const NUMBER = /^[+\-−±]?[$€£¥₽₪]?\s?\d[\d\s.,’'  ]*\s?(?:%|‰|[$€£¥₽₪]|[a-zа-яё]{1,4}\.?)?$/i;
  function startsBlock(lines, i) {
    const line = lines[i];
    if (fence(line) || heading(line) || rule(line) || quote(line)) return true;
    const item = listItem(line);
    if (item && item.content.trim() && (!item.ordered || item.number === 1)) return true;
    return Boolean(tableStart(lines, i));
  }

  function parseBlocks(lines, depth) {
    const blocks = [];
    if (depth > MAX_DEPTH) {
      const text = lines.join('\n').trim();
      if (text) blocks.push({ type: 'paragraph', children: [{ type: 'text', text }] });
      return blocks;
    }
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      if (blank(line)) { i++; continue; }
      const open = fence(line);
      if (open) {
        const body = [];
        let j = i + 1;
        for (; j < lines.length; j++) {
          const close = fence(lines[j]);
          if (close && close.ch === open.ch && close.length >= open.length && !close.info) break;
          let k = 0; while (k < open.indent && lines[j][k] === ' ') k++;
          body.push(lines[j].slice(k));
        }
        blocks.push({ type: 'code', language: open.info.split(/\s/)[0] || '', text: body.join('\n') });
        i = j + 1; continue;
      }
      const title = heading(line);
      if (title) { blocks.push({ type: 'heading', level: title.level, children: parseInline(title.content) }); i++; continue; }
      if (rule(line)) { blocks.push({ type: 'rule' }); i++; continue; }
      if (quote(line)) {
        const inner = [];
        while (i < lines.length && quote(lines[i])) { inner.push(lines[i].replace(/^ {0,3}> ?/, '')); i++; }
        blocks.push({ type: 'quote', blocks: parseBlocks(inner, depth + 1) });
        continue;
      }
      const first = listItem(line);
      if (first) { i = parseList(lines, i, first, depth, blocks); continue; }
      const align = tableStart(lines, i);
      if (align) {
        const header = cells(line).map(parseInline);
        const raw = [];
        let j = i + 2;
        for (; j < lines.length && !blank(lines[j]) && lines[j].includes('|') && !fence(lines[j]) && !quote(lines[j]); j++) {
          const row = cells(lines[j]);
          raw.push(Array.from({ length: align.length }, (_, c) => row[c] ?? ''));
        }
        const numeric = align.map((_, c) => {
          let seen = 0;
          for (const row of raw) { const value = row[c].replace(/[*_`]/g, '').trim(); if (!value) continue; if (!NUMBER.test(value)) return false; seen++; }
          return seen > 0;
        });
        blocks.push({ type: 'table', align, numeric, header, rows: raw.map(row => row.map(parseInline)) });
        i = j; continue;
      }
      const paragraph = [line.trim()];
      i++;
      while (i < lines.length && !blank(lines[i]) && !startsBlock(lines, i)) { paragraph.push(lines[i].trim()); i++; }
      blocks.push({ type: 'paragraph', children: parseInline(paragraph.join('\n')) });
    }
    return blocks;
  }

  function parseList(lines, i, first, depth, blocks) {
    const list = { type: 'list', ordered: first.ordered, start: first.ordered ? first.number : 1, items: [] };
    const sameKind = item => item && item.ordered === first.ordered && item.kind === first.kind && item.indent < first.width;
    let item = first;
    while (item) {
      const body = [item.content];
      let j = i + 1, next = null;
      while (j < lines.length) {
        const line = lines[j];
        if (blank(line)) {
          let k = j; while (k < lines.length && blank(lines[k])) k++;
          if (k === lines.length) { j = k; break; }
          if (indentOf(lines[k]) >= item.width) { for (; j < k; j++) body.push(''); continue; }
          const sibling = listItem(lines[k]);
          if (sameKind(sibling) && sibling.indent < item.width) { next = sibling; j = k; }
          break;
        }
        if (indentOf(line) >= item.width) { body.push(line.slice(item.width)); j++; continue; }
        const sibling = listItem(line);
        if (sibling) { if (sameKind(sibling)) next = sibling; break; }
        if (fence(line) || heading(line) || rule(line) || quote(line)) break;
        body.push(line.trim()); j++;
      }
      list.items.push({ blocks: parseBlocks(body, depth + 1) });
      i = j;
      item = next;
      if (!next) break;
    }
    blocks.push(list);
    return i;
  }

  function parse(source) {
    const text = String(source ?? '').replace(/\r\n?/g, '\n').replace(/^\t+/gm, tabs => '    '.repeat(tabs.length));
    return parseBlocks(text.split('\n'), 0);
  }

  // ---------- DOM ----------

  function render(source, doc, options = {}) {
    const fragment = doc.createDocumentFragment();
    const text = String(source ?? '');
    if (text.length > LIMIT) {
      const p = doc.createElement('p'); p.className = 'plain'; p.dir = 'auto'; p.textContent = text;
      fragment.append(p);
      return fragment;
    }
    renderBlocks(parse(text), fragment, doc, options);
    return fragment;
  }

  function renderBlocks(blocks, parent, doc, options) {
    for (const block of blocks) {
      let element;
      switch (block.type) {
        case 'paragraph': element = doc.createElement('p'); renderInline(block.children, element, doc); break;
        case 'heading': element = doc.createElement('h' + Math.min(6, block.level)); renderInline(block.children, element, doc); break;
        case 'rule': element = doc.createElement('hr'); break;
        case 'quote': element = doc.createElement('blockquote'); renderBlocks(block.blocks, element, doc, options); break;
        case 'code': element = codeBlock(block, doc, options); break;
        case 'table': element = table(block, doc); break;
        case 'list': element = list(block, doc, options); break;
        default: continue;
      }
      if (block.type !== 'code' && block.type !== 'rule') element.dir = 'auto';
      parent.append(element);
    }
  }

  function list(block, doc, options) {
    const element = doc.createElement(block.ordered ? 'ol' : 'ul');
    element.setAttribute('role', 'list');
    if (block.ordered && block.start !== 1) element.start = block.start;
    const last = block.start + block.items.length - 1;
    if (block.ordered && String(last).length > 1) element.className = 'wide';
    block.items.forEach((entry, index) => {
      const item = doc.createElement('li'); item.dir = 'auto';
      const marker = doc.createElement('span'); marker.className = 'marker'; marker.setAttribute('aria-hidden', 'true');
      marker.textContent = block.ordered ? (block.start + index) + '.' : '•';
      const body = doc.createElement('div'); body.className = 'item';
      renderBlocks(entry.blocks, body, doc, options);
      item.append(marker, body);
      element.append(item);
    });
    return element;
  }

  function codeBlock(block, doc, options) {
    const wrap = doc.createElement('div'); wrap.className = 'code-block';
    const pre = doc.createElement('pre'); pre.dir = 'ltr';
    const code = doc.createElement('code'); code.textContent = block.text;
    if (block.language) code.setAttribute('data-language', block.language);
    pre.append(code);
    const label = options.label || (key => ({ 'Скопировать код': 'Copy code', 'Код скопирован': 'Code copied' })[key] || key);
    const button = doc.createElement('button'); button.type = 'button'; button.className = 'copy';
    button.setAttribute('aria-label', label('Скопировать код')); button.title = label('Скопировать код');
    button.append(options.icon ? options.icon('copy') : label('Скопировать код'));
    button.addEventListener('click', () => copy(code, button, label, options));
    wrap.append(pre, button);
    return wrap;
  }

  function copy(code, button, label, options) {
    const done = () => {
      button.setAttribute('aria-label', label('Код скопирован')); button.title = label('Код скопирован');
      button.dataset.copied = 'true';
      if (options.icon) button.replaceChildren(options.icon('check'));
      setTimeout(() => {
        button.setAttribute('aria-label', label('Скопировать код')); button.title = label('Скопировать код');
        delete button.dataset.copied;
        if (options.icon) button.replaceChildren(options.icon('copy'));
      }, 1500);
    };
    const select = () => { const range = code.ownerDocument.createRange(); range.selectNodeContents(code); const selection = code.ownerDocument.getSelection(); selection.removeAllRanges(); selection.addRange(range); };
    const clipboard = root.navigator?.clipboard;
    if (clipboard?.writeText) clipboard.writeText(code.textContent).then(done, select);
    else select();
  }

  function table(block, doc) {
    const wrap = doc.createElement('div'); wrap.className = 'table-wrap';
    const element = doc.createElement('table');
    const cellClass = column => [block.numeric[column] ? 'numeric' : '', block.align[column] ? 'align-' + block.align[column] : ''].filter(Boolean).join(' ');
    const head = doc.createElement('thead'), headRow = doc.createElement('tr');
    block.header.forEach((cell, column) => {
      const th = doc.createElement('th'); th.setAttribute('scope', 'col'); th.className = cellClass(column);
      renderInline(cell, th, doc); headRow.append(th);
    });
    head.append(headRow);
    const body = doc.createElement('tbody');
    for (const row of block.rows) {
      const tr = doc.createElement('tr');
      row.forEach((cell, column) => { const td = doc.createElement('td'); td.className = cellClass(column); renderInline(cell, td, doc); tr.append(td); });
      body.append(tr);
    }
    element.append(head, body);
    wrap.append(element);
    return wrap;
  }

  function renderInline(nodes, parent, doc) {
    for (const node of nodes) {
      switch (node.type) {
        case 'text': parent.append(doc.createTextNode(node.text)); break;
        case 'break': parent.append(doc.createElement('br')); break;
        case 'code': { const code = doc.createElement('code'); code.textContent = node.text; parent.append(code); break; }
        case 'strong': case 'em': case 'del': { const element = doc.createElement(node.type); renderInline(node.children, element, doc); parent.append(element); break; }
        case 'link': {
          const href = safeHref(node.href);
          if (!href) { renderInline(node.children, parent, doc); break; }
          const a = doc.createElement('a');
          a.href = href; a.rel = 'noopener noreferrer nofollow'; a.target = '_blank';
          renderInline(node.children, a, doc);
          parent.append(a);
          break;
        }
      }
    }
  }

  // ---------- Time clusters ----------

  /* Some imported history knows only the day, so it has no honest time. */
  function moment(message) {
    const value = String(message?.createdAt ?? '');
    const dayOnly = Boolean(message?.imported) && /T00:00:00(?:\.0+)?Z$/.test(value);
    if (dayOnly) {
      const [year, month, day] = value.slice(0, 10).split('-').map(Number);
      const date = new Date(year, month - 1, day);
      return Number.isNaN(date.getTime()) ? null : { date, hasTime: false };
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : { date, hasTime: true };
  }
  const sameDay = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

  /* A cluster starts on a new day or after a gap of 30 minutes or more. */
  function timeBreaks(messages) {
    const breaks = [];
    let previous = null;
    messages.forEach((message, index) => {
      const current = moment(message);
      if (!current) return;
      const starts = !previous || !sameDay(previous.date, current.date)
        || (current.hasTime && !previous.hasTime)
        || (current.hasTime && current.date - previous.date >= CLUSTER_GAP);
      if (starts) breaks.push({ index, date: current.date, hasTime: current.hasTime });
      previous = current;
    });
    return breaks;
  }

  root.StrudelMarkdown = { parse, parseInline, render, safeHref, timeBreaks, moment, limit: LIMIT };
})(globalThis);
