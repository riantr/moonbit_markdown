/**
 * Build a paginated PDF from the Mermaid state diagram.
 *
 * Why a custom print layout instead of "print the HTML page":
 *   - the overview graph is 1,117 x 25,160 px; the f98 detail is 16,301 x 1,819 px.
 *     Printing either whole would scale it to 3-6% and be unreadable.
 *   - so the overview is re-rendered as 19 readable slices (12 files each, real
 *     mermaid renders with the true edge labels), and the actionable file's
 *     detail is printed as a key map of the full diagram + the actionable
 *     finding enlarged + its notices as a list.
 *   - the complete data (all 221 files, all 2,147 notices) is emitted as
 *     paginated tables, so nothing in the source is lost.
 *
 * Everything is rendered by mermaid in a real browser, so the PDF carries the
 * same drawing as the HTML5 page.
 */
const fs = require('fs');
const path = require('path');
const puppeteer = require('C:/Users/hp/AppData/Roaming/npm/node_modules/@mermaid-js/mermaid-cli/node_modules/puppeteer');

const ROOT = 'D:\\src\\moon\\moonbit_markdown';
const SRC = path.join(ROOT, 'riantr-moonbit_doubleML_0.164.28_0.1.20261012_20261023T005706Z.mmd');
const MERMAID_MIN = 'C:\\Users\\hp\\AppData\\Roaming\\npm\\node_modules\\@mermaid-js\\mermaid-cli\\node_modules\\mermaid\\dist\\mermaid.min.js';
const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const OUT_PDF = path.join(ROOT, 'moonbit_doubleML_state_diagram.pdf');

const EM = String.fromCharCode(8212);
const SLICE_FILES = 12;      // files per overview slice

// ---------------------------------------------------------------- parse
const lines = fs.readFileSync(SRC, 'utf8').split(/\r?\n/);
const meta = {};
for (const L of lines) {
  const s = L.trim();
  if (!s.startsWith('%%')) continue;
  for (const pair of s.replace(/^%+\s*/, '').split(/\s+/)) {
    const i = pair.indexOf('=');
    if (i > 0 && !(pair.slice(0, i) in meta)) meta[pair.slice(0, i)] = pair.slice(i + 1);
  }
}
let firstEdge = lines.findIndex((l) => /^ {4}scan --> f\d+ :/.test(l));
const blocks = [];
let cur = null;
for (const L of lines.slice(firstEdge)) {
  const m = /^ {4}scan --> (f\d+) :/.exec(L);
  if (m) { cur = { id: m[1], lines: [L] }; blocks.push(cur); continue; }
  if (cur) { cur.lines.push(L); if (/^ {4}\}$/.test(L)) cur = null; }
}
const files = blocks.map((b) => {
  const pathLine = b.lines.find((l) => /^ {4}state "/.test(l)) || '';
  const fp = /^ {4}state "f\d+ \u2014 (.*)" as f\d+ \{$/.exec(pathLine);
  const edge = b.lines[0];
  const notices = [], findings = [];
  for (const L of b.lines) {
    const sm = /^\s+state "(.*?)" as ([A-Za-z0-9_]+)\s*$/.exec(L);
    if (!sm) continue;
    if (sm[1].startsWith('NOTICE ' + EM + ' ')) notices.push({ id: sm[2], msg: sm[1] });
    else if (!/^f\d+ \u2014 /.test(sm[1]) && !/^(lexed|inspection [123]\/3)/.test(sm[1])) {
      findings.push({ id: sm[2], msg: sm[1] });
    }
  }
  return {
    id: b.id,
    path: fp ? fp[1] : '',
    name: fp ? fp[1].split('/').pop() : b.id,
    actionable: +(edge.match(/(\d+) actionable/) || [, 0])[1],
    noticeCount: +(edge.match(/(\d+) notice\(s\)/) || [, 0])[1],
    notices, findings,
    lines: b.lines,
    src: ['stateDiagram-v2', '    direction TB', ...b.lines].join('\n'),
  };
});
const actionableFiles = files.filter((f) => f.actionable > 0);
const allNotices = files.flatMap((f) => f.notices.map((n) => ({ file: f, n })));
const allFindings = files.flatMap((f) => f.findings.map((n) => ({ file: f, n })));
console.log(`parsed ${files.length} files, ${allNotices.length} notices, ${allFindings.length} findings`);

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/**
 * mermaid emits <svg width="100%" style="max-width:Npx" viewBox="0 0 W H"> with no
 * height. Inside a print holder with no intrinsic width, width="100%" collapses
 * to 0 and the page comes out blank. Pin width/height to the natural size and
 * neutralise the max-width clamp, optionally re-basing the viewBox to crop.
 */
function normalizeSvg(svg, w, h, vx, vy, vw, vh) {
  let s = svg
    .replace(/style="max-width:[^"]*"/, 'style="max-width:none"')
    .replace(/<svg([^>]*)>/, (m, attrs) => {
      let a = attrs
        .replace(/\s*width="[^"]*"/, '')
        .replace(/\s*height="[^"]*"/, '')
        .replace(/\s*viewBox="[^"]*"/, '');
      return `<svg${a} width="${w}" height="${h}" viewBox="${vx} ${vy} ${vw} ${vh}">`;
    });
  return s;
}

/**
 * The same detail SVG is embedded once per crop, so its root id (and the
 * marker ids derived from it) would repeat in the document. Re-scope them so
 * each crop's <style> and url(#...) references stay self-consistent.
 */
function reIdSvg(svg, oldId, newId) {
  return svg.split(oldId).join(newId);
}

/**
 * The 27 NOTICE states of the actionable file each carry the SAME boilerplate
 * footnote (294px tall, 230px wide) - 27 identical boxes that made the diagram
 * 16,302px wide and forced it into 13 unreadable slices.
 *
 * For the focused print view we keep the diagram's substance - the trust chain,
 * the "27 of the findings are NOTICES" note and the actionable finding with its
 * WHY note - and drop only the 27 duplicated boilerplate notes. Every node and
 * every edge of the chain stays; the boilerplate text is printed once, in full,
 * as a legend next to the notice list.
 */
function focusSource(blockLines) {
  const out = [];
  let inNote = false, keepNote = false;
  for (const L of blockLines) {
    const nm = /^\s*note right of (\S+)/.exec(L);
    if (nm) {
      inNote = true;
      // keep the file-level note and the WHY note; drop the 27 copies
      keepNote = !/^f98_n\d+$/.test(nm[1]);
      if (keepNote) out.push(L);
      continue;
    }
    if (inNote) {
      if (/^\s*end note\s*$/.test(L)) { inNote = false; if (keepNote) out.push(L); }
      else if (keepNote) out.push(L);
      continue;
    }
    if (/f98_n\d+/.test(L)) continue;          // drop the notice fan
    out.push(L);
  }
  return ['stateDiagram-v2', '    direction TB', ...out].join('\n');
}

/**
 * Classify the nodes of the actionable file's diagram by IDENTITY, not by text:
 * mermaid renders a note as a node too (id "...----note-8"), and the note text
 * repeats the word NOTICE, so a text match counts 27 states + 27 note boxes.
 */
function classifyNodes(nodes, fileId) {
  const reState = new RegExp(`^state-${fileId}_n\\d+-\\d+$`);
  const reDefect = new RegExp(`^state-${fileId}_e8-\\d+$`);
  const reChain = new RegExp(`^state-(${fileId}|scan)(_(lex|struct|type|behav|start|end))?-\\d+$`);
  const reBoiler = new RegExp(`^state-${fileId}_n\\d+----note-\\d+$`);
  const reWhy = new RegExp(`^state-${fileId}_e8----note-\\d+$`);
  const reFileNote = new RegExp(`^state-${fileId}_struct----note-\\d+$`);

  const g = { states: [], boiler: [], chain: [], defect: [], why: [], fileNote: [] };
  for (const n of nodes) {
    if (reWhy.test(n.id)) { g.why.push(n); continue; }
    if (reFileNote.test(n.id)) { g.fileNote.push(n); continue; }
    if (reBoiler.test(n.id)) { g.boiler.push(n); continue; }
    if (reDefect.test(n.id)) { g.defect.push(n); continue; }
    if (reState.test(n.id)) { g.states.push(n); continue; }
    if (reChain.test(n.id)) { g.chain.push(n); continue; }
  }
  const span = (arr) => arr.length
    ? [Math.min(...arr.map((n) => n.x)), Math.max(...arr.map((n) => n.x + n.w))]
    : [0, 0];
  g.span = {
    chain: span(g.chain), states: span(g.states), boiler: span(g.boiler),
    defect: span(g.defect), why: span(g.why),
  };
  return g;
}

// ---------------------------------------------------------------- html
function coverHtml() {
  const c = (k) => esc(meta[k] || '');
  const findingsRows = allFindings.map(({ file, n }) => `
    <tr>
      <td class="mono">${esc(file.id)}</td>
      <td class="mono">${esc(n.id)}</td>
      <td>${esc(n.msg)}</td>
      <td class="mono">${esc(file.path)}</td>
    </tr>`).join('');
  return `
  <div class="page cover">
    <h1>riantr/moonbit_doubleML</h1>
    <h2>Mermaid <code>stateDiagram-v2</code> &mdash; HTML5 render, printed to PDF</h2>
    <div class="rule"></div>
    <table class="kv">
      <tr><th>target</th><td class="mono">${c('target')}</td></tr>
      <tr><th>version</th><td class="mono">${c('version')}</td></tr>
      <tr><th>moonbit</th><td class="mono">${c('moonbit')}</td></tr>
      <tr><th>scanned at</th><td class="mono">${c('scanned_at')}</td></tr>
      <tr><th>files</th><td>${c('files')}</td></tr>
      <tr><th>parsed</th><td>${c('parsed')}</td></tr>
      <tr><th>partial</th><td>${c('partial')}</td></tr>
      <tr><th>actionable</th><td>${c('actionable')}</td></tr>
      <tr><th>notices</th><td>${c('notices')}</td></tr>
      <tr><th>unreliable</th><td>${c('unreliable')}</td></tr>
      <tr><th>withheld</th><td>${c('withheld')}</td></tr>
      <tr><th>total findings</th><td>${c('total')}</td></tr>
    </table>

    <h3>How to read this diagram</h3>
    <p>The trust chain, not the counts, is the point. Each of the ${c('files')} files
    is scanned by the same three inspections &mdash; <em>structural</em>, <em>type</em>,
    <em>behavioral</em> &mdash; after a lex pass. A file's findings hang off its
    <em>inspection 1/3 &mdash; structural</em> state.</p>
    <p>Nearly every finding is a <strong>NOTICE</strong>: a declaration form the
    analyzer does not model was read but not analysed. Notices are counted in
    <code>notices</code> and are <em>excluded</em> from <code>actionable</code>; they are
    not defects, even though they are drawn like them. Exactly
    <strong>${c('actionable')}</strong> finding in this scan is a real defect:</p>
    <table class="data">
      <thead><tr><th>file</th><th>state</th><th>finding</th><th>path</th></tr></thead>
      <tbody>${findingsRows}</tbody>
    </table>

    <h3>Contents</h3>
    <ul class="toc">
      <li><b>Overview</b> &mdash; the <code>scan</code> node and all ${c('files')} files with their
          per-file finding counts, split across ${Math.ceil(files.length / SLICE_FILES)} pages.</li>
      <li><b>Detail: ${esc(actionableFiles.map((f) => f.id).join(', '))}</b> &mdash; the one file with an
          actionable finding, in <span id="cropcount">3</span> pages: a <b>key map</b> of the full
          diagram, the <b>actionable finding enlarged</b> from the real render, and the
          file's <b>notices as a list</b> with the shared footnote printed once.</li>
      <li><b>Appendix A</b> &mdash; all ${c('files')} files, their paths and finding counts.</li>
      <li><b>Appendix B</b> &mdash; all ${allNotices.length} notice states, with their source locations.</li>
    </ul>

    <h3>Notes on this rendering</h3>
    <ul class="notes">
      <li>The source is 21,187 lines with 3,254 states and 2,371 notes. Mermaid's
          layout engine (dagre) cannot lay out this graph in one piece &mdash; it
          fails in <code>order/index.js</code> with
          <code>Cannot set properties of undefined (setting 'order')</code> once
          more than ~30 compound states carry notes.</li>
      <li>${esc(actionableFiles.map((f) => f.id).join(', '))} is drawn as a 16,302&nbsp;px
          wide strip whose 27 NOTICE states each carry the <em>same</em> footnote;
          sliced across pages it filled 13 sheets at roughly 8&nbsp;px type. The detail
          section prints a key map of the strip, the actionable finding enlarged from
          the real render, and the 27 notices as a list &mdash; same content, readable
          size.</li>
      <li>The header reports ${c('notices')} notices, but the source draws
          ${allNotices.length} notice <em>states</em>: the generator caps notice
          states at 40 per file, so 6 files show fewer nodes than their edge label
          claims. This PDF reproduces the source as-is.</li>
      <li>Per-file diagrams for the other ${files.length - actionableFiles.length} files
          stay interactive in the HTML5 page; their complete notice data is in
          Appendix B.</li>
    </ul>
  </div>`;
}

function fileTableHtml() {
  const rows = files.map((f) => `
    <tr class="${f.actionable ? 'hot' : ''}">
      <td class="mono">${esc(f.id)}</td>
      <td class="mono path">${esc(f.path)}</td>
      <td class="num">${f.actionable}</td>
      <td class="num">${f.noticeCount}</td>
      <td class="num">${f.notices.length}</td>
      <td class="num">${f.findings.length}</td>
    </tr>`).join('');
  return `
  <div class="page flow">
    <h3 class="appx">Appendix A &mdash; all scanned files</h3>
    <table class="data">
      <thead><tr>
        <th>file</th><th>path</th><th class="num">actionable</th>
        <th class="num">notices (label)</th><th class="num">notice states</th>
        <th class="num">findings</th>
      </tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </div>`;
}

function noticeTableHtml() {
  const rows = allNotices.map(({ file, n }) => {
    const mm = /^(NOTICE \u2014 )?([A-Za-z]+)( @([\d:]+))? \u2014 (.*)$/.exec(n.msg);
    const kind = mm ? mm[2] : 'NOTICE';
    const loc = mm && mm[4] ? mm[4] : '';
    const text = mm ? mm[5] : n.msg;
    return `
    <tr>
      <td class="mono">${esc(file.id)}</td>
      <td class="mono">${esc(n.id)}</td>
      <td>${esc(kind)}</td>
      <td class="mono">${esc(loc)}</td>
      <td>${esc(text)}</td>
    </tr>`;
  }).join('');
  return `
  <div class="page flow">
    <h3 class="appx">Appendix B &mdash; all ${allNotices.length} notice states</h3>
    <p class="lede">Every notice below is excluded from the <code>actionable</code>
    count. They are declaration forms the analyzer does not model, not defects.</p>
    <table class="data notices">
      <thead><tr>
        <th>file</th><th>state</th><th>kind</th><th>loc</th><th>message</th>
      </tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </div>`;
}

const PRINT_CSS = `
  @page { size: A4 portrait; margin: 12mm; }
  * { box-sizing: border-box; }
  body { margin:0; background:#fff; color:#111;
         font:10.5pt/1.45 "Segoe UI", Arial, Helvetica, sans-serif; }
  .page { width:186mm; height:273mm; page-break-after:always; break-after:page;
          position:relative; overflow:hidden; padding:0; }
  .page:last-child { page-break-after:auto; break-after:auto; }
  .page.flow { height:auto; min-height:0; }   /* appendix tables may run long */
  h1 { font-size:24pt; margin:0 0 4pt; letter-spacing:-.3pt; }
  h2 { font-size:12pt; font-weight:500; color:#555; margin:0 0 10pt; }
  h3 { font-size:12pt; margin:16pt 0 5pt; }
  h3.appx { margin:0 0 8pt; }
  code, .mono { font-family:Consolas, "Courier New", monospace; font-size:9pt; }
  .rule { height:2px; background:#111; margin:0 0 12pt; }
  table.kv { border-collapse:collapse; width:100%; margin-bottom:6pt; }
  table.kv th { text-align:left; width:26%; color:#555; font-weight:500; padding:1.5pt 8pt 1.5pt 0;
                vertical-align:top; }
  table.kv td { padding:1.5pt 0; }
  table.data { border-collapse:collapse; width:100%; font-size:8.6pt; }
  table.data th { text-align:left; background:#ececec; border-bottom:1px solid #999;
                  padding:3pt 5pt; font-weight:600; }
  table.data td { border-bottom:1px solid #e2e2e2; padding:2.2pt 5pt; vertical-align:top; }
  table.data tr { page-break-inside:avoid; break-inside:avoid; }
  table.data thead { display:table-header-group; }
  table.data td.num { text-align:right; font-variant-numeric:tabular-nums; }
  table.data td.path { word-break:break-all; }
  table.data tr.hot td { background:#fff6e0; }
  table.notices td:nth-child(5) { width:52%; }
  .cover ul.toc, .cover ul.notes { padding-left:14pt; margin:4pt 0 0; font-size:9.6pt; }
  .cover ul.notes li { margin:2pt 0; }
  .cover p { font-size:9.8pt; margin:4pt 0; }
  .lede { font-size:9.6pt; color:#444; margin:0 0 8pt; }
  .crop { position:relative; overflow:hidden; }
  .crop > .holder { position:absolute; left:0; top:0; transform-origin:0 0; }
  .slice-cap { font-size:8.4pt; color:#666; margin:0 0 4pt; height:14pt; }
  .km { position:relative; width:186mm; margin:0 0 7pt; }
  .km-svg { position:relative; width:100%; }
  .km-svg svg { display:block; width:100%; height:auto; }
  .km-tick { position:absolute; top:0; width:1px; height:100%; background:#c9c9c9; }
  .km-tick.hot { background:#c0392b; width:1.5px; }
  .km-band { position:absolute; top:0; height:100%; background:rgba(70,110,190,.10);
             border-left:1px solid #7d9cc4; border-right:1px solid #7d9cc4; }
  .km-labs { position:relative; height:11pt; }
  .km-lab { position:absolute; top:0; font-size:6.2pt; font-weight:400; color:#666;
            transform:translateX(-50%); white-space:nowrap; }
  .km-lab.hot { color:#c0392b; font-weight:700; }
  .km-lab.band { color:#3c5f91; }
  table.keymap-tbl { font-size:8.4pt; margin-bottom:7pt; }
  table.keymap-tbl tr.hot td { background:#fff6e0; }
  blockquote.boiler { margin:4pt 0 8pt; padding:5pt 8pt; background:#f5f5f5;
                      border-left:3px solid #999; font-size:8.4pt; color:#333; }
`;

// ---------------------------------------------------------------- render
(async () => {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
    headless: 'new',
    protocolTimeout: 1800000,
  });
  const page = await browser.newPage();
  await page.setDefaultTimeout(1800000);
  await page.setContent(`<!DOCTYPE html><html><head><meta charset="utf-8">
    <style>${PRINT_CSS}</style></head><body><div id="doc"></div></body></html>`);
  await page.addScriptTag({ path: MERMAID_MIN });
  await page.evaluate(() => {
    window.mermaid.initialize({ startOnLoad: false, maxTextSize: 20000000, maxEdges: 500000, theme: 'default' });
  });

  // ---- inject the cover first; slices/details/appendices are appended after
  //      it in order, so the document reads: cover, overview, detail, tables.
  await page.evaluate((cover) => {
    document.getElementById('doc').innerHTML = cover;
  }, coverHtml());

  // ---- overview slices (real mermaid renders)
  const sliceCount = Math.ceil(files.length / SLICE_FILES);
  for (let i = 0; i < sliceCount; i++) {
    const chunk = files.slice(i * SLICE_FILES, (i + 1) * SLICE_FILES);
    const src = ['stateDiagram-v2', '    direction LR']
      .concat(chunk.map((f) => `    state "${f.id} ${EM} ${f.path}" as ${f.id}`))
      .concat([`    state "scan ${EM} ${meta.target || ''}" as scan`])
      .concat(chunk.map((f) => `    scan --> ${f.id} : ${f.actionable} actionable, ${f.noticeCount} notice(s), parsed`))
      .join('\n');
    const r = await page.evaluate(async (src, id) => {
      try {
        const { svg } = await window.mermaid.render(id, src);
        const vb = (svg.match(/viewBox="([^"]+)"/) || [, ''])[1].split(/[ ,]+/).map(Number);
        return { ok: true, svg, w: vb[2], h: vb[3] };
      } catch (e) { return { ok: false, err: (e && e.message) || String(e) }; }
    }, src, 'sl_' + i);
    if (!r.ok) { console.log(`slice ${i} FAILED: ${r.err}`); continue; }
    const norm = normalizeSvg(r.svg, r.w, r.h, 0, 0, r.w, r.h);
    await page.evaluate((html, w, h, cap) => {
      const doc = document.getElementById('doc');
      const p = document.createElement('div');
      p.className = 'page';
      const c = document.createElement('p');
      c.className = 'slice-cap';
      c.textContent = cap;
      const win = document.createElement('div');
      win.className = 'crop';
      // A4 portrait minus the 12mm print margins is 186mm x 273mm. The caption
      // sits above the crop, so measure it and give the crop only what is
      // left - otherwise the page overflows onto a second, blank sheet.
      // The page must already be in the document for the measurement to work.
      const WC = 186 * 96 / 25.4, PAGE_H = 273 * 96 / 25.4;
      p.appendChild(c);
      doc.appendChild(p);          // measure in-document
      const capH = c.getBoundingClientRect().height +
        parseFloat(getComputedStyle(c).marginBottom || 0);
      const HC = PAGE_H - capH;
      const scale = Math.min(WC / w, HC / h);
      win.style.width = WC + 'px'; win.style.height = HC + 'px';
      const holder = document.createElement('div');
      holder.className = 'holder';
      holder.style.transform = `scale(${scale})`;
      holder.innerHTML = html;
      win.appendChild(holder);
      p.appendChild(win);
      doc.appendChild(p);   // keep document order = logical order
    }, norm, r.w, r.h, `Overview ${i + 1}/${sliceCount} — files ${chunk[0].id}..${chunk[chunk.length - 1].id}`);
    console.log(`slice ${i + 1}/${sliceCount} rendered  ${Math.round(r.w)}x${Math.round(r.h)}`);
  }

  // ---- detail section of the actionable file
  //
  // The faithful diagram is 16,302 x 1,819 px: 54 columns, of which 27 carry a
  // 230x294px footnote whose text is IDENTICAL in all 27 cases. Slicing it into
  // page-width windows therefore cost 13 pages and still left the label text at
  // ~8px, and the single actionable finding sat in the middle of the strip.
  //
  // The print layout replaces the strip with three pages that carry the same
  // information at readable size:
  //   1. a key map  - the real diagram, scaled to fit the page width, with
  //      tick marks showing where the chain, the notice fan and the defect
  //      are (this is the orientation the reader lost);
  //   2. the actionable finding, enlarged, as a true crop of the real SVG;
  //   3. the 27 notices as a table, with the shared boilerplate footnote
  //      printed once in full.
  const act = actionableFiles[0];
  if (act) {
    /** render a diagram and measure every node in viewBox units */
    const measured = (src, id) => page.evaluate(async (src, id) => {
      try {
        const { svg } = await window.mermaid.render(id, src);
        const vb = (svg.match(/viewBox="([^"]+)"/) || [, ''])[1].split(/[ ,]+/).map(Number);
        // Measure the diagram at its natural size so getCTM is the identity
        // and the numbers are in viewBox units.
        const d = document.createElement('div');
        d.style.cssText = 'position:absolute;left:0;top:0;';
        d.innerHTML = svg;
        document.body.appendChild(d);
        const el = d.querySelector('svg');
        el.setAttribute('width', String(vb[2]));
        el.setAttribute('height', String(vb[3]));
        el.removeAttribute('style');
        const nodes = [];
        for (const e of el.querySelectorAll('g.node')) {
          let b;
          try { b = e.getBBox(); } catch (err) { continue; }
          if (!b) continue;
          const m = e.getCTM();
          if (!m) continue;
          const p0 = new DOMPoint(b.x, b.y).matrixTransform(m);
          const p1 = new DOMPoint(b.x + b.width, b.y + b.height).matrixTransform(m);
          nodes.push({
            id: e.getAttribute('id') || '',
            x: p0.x, y: p0.y, w: p1.x - p0.x, h: p1.y - p0.y,
            text: (e.textContent || '').trim(),
          });
        }
        d.remove();
        return { ok: true, svg, w: vb[2], h: vb[3], nodes };
      } catch (e) { return { ok: false, err: (e && e.message) || String(e) }; }
    }, src, id);

    const full = await measured(act.src, 'detfull_' + act.id);
    if (!full.ok) {
      console.log('detail render FAILED: ' + full.err);
    } else {
      const foc = await measured(focusSource(act.lines), 'detfoc_' + act.id);
      if (!foc.ok) console.log('focused render FAILED: ' + foc.err);

      const cls = classifyNodes(full.nodes, act.id);
      const WC = 186 * 96 / 25.4, PAGE_H = 273 * 96 / 25.4;
      const toPx = (x) => (x / full.w) * WC;

      // ---------- page 1: key map of the real diagram
      const mapH = (full.h / full.w) * WC;
      const thumb = normalizeSvg(full.svg, WC, mapH, 0, 0, full.w, full.h);
      const clamp = (x) => Math.max(22, Math.min(WC - 22, x));
      // ticks under the 27 NOTICE states
      const ticks = cls.states.map((n) =>
        `<i class="km-tick" style="left:${toPx(n.x + n.w / 2).toFixed(1)}px"></i>`).join('');
      const nLabels = cls.states.map((n, i) => {
        if (!(i % 7 === 0 || i === cls.states.length - 1)) return '';
        return `<b class="km-lab" style="left:${toPx(n.x + n.w / 2).toFixed(1)}px">n${i}</b>`;
      }).join('');
      // the band that holds the 27 identical footnotes
      const bL = toPx(cls.span.boiler[0]).toFixed(1);
      const bW = (toPx(cls.span.boiler[1]) - toPx(cls.span.boiler[0])).toFixed(1);
      const defectX = cls.defect.length ? toPx(cls.defect[0].x + cls.defect[0].w / 2) : null;
      const whyX = cls.why.length ? toPx(cls.why[0].x + cls.why[0].w / 2) : null;
      const gapPx = defectX !== null && whyX !== null ? Math.round(whyX - defectX) : 0;
      const gapOrig = cls.why.length && cls.defect.length
        ? Math.round(cls.why[0].x - cls.defect[0].x) : 0;

      await page.evaluate((html, cap) => {
        const doc = document.getElementById('doc');
        const p = document.createElement('div');
        p.className = 'page';
        const c = document.createElement('p');
        c.className = 'slice-cap';
        c.textContent = cap;
        p.appendChild(c);
        const box = document.createElement('div');
        box.innerHTML = html;
        while (box.firstChild) p.appendChild(box.firstChild);
        doc.appendChild(p);
      }, `
        <div class="km">
          <div class="km-svg">${thumb}
            <i class="km-band" style="left:${bL}px;width:${bW}px"></i>
            ${ticks}
            ${defectX !== null ? `<i class="km-tick hot" style="left:${clamp(defectX).toFixed(1)}px"></i>` : ''}
            ${whyX !== null ? `<i class="km-tick hot" style="left:${clamp(whyX).toFixed(1)}px"></i>` : ''}
          </div>
          <div class="km-labs">
            ${nLabels}
            ${defectX !== null ? `<b class="km-lab hot" style="left:${clamp(defectX).toFixed(1)}px">the finding</b>` : ''}
            ${whyX !== null ? `<b class="km-lab hot" style="left:${clamp(whyX).toFixed(1)}px">its WHY note</b>` : ''}
          </div>
          <div class="km-labs">
            <b class="km-lab band" style="left:${(parseFloat(bL) + parseFloat(bW) / 2).toFixed(1)}px">27 identical footnotes</b>
          </div>
        </div>
        <table class="data keymap-tbl">
          <thead><tr><th>region of the real diagram</th><th class="num">x range (px)</th><th>what is there</th><th>where it is printed</th></tr></thead>
          <tbody>
            <tr><td>trust chain</td><td class="num">${Math.round(cls.span.chain[0])}&ndash;${Math.round(cls.span.chain[1])}</td>
                <td>scan &rarr; ${act.id} &rarr; lexed &rarr; inspection 1/3 &rarr; 2/3 &rarr; 3/3</td>
                <td>page ${sliceCount + 3}, enlarged</td></tr>
            <tr><td>NOTICE states</td><td class="num">${Math.round(cls.span.states[0])}&ndash;${Math.round(cls.span.states[1])}</td>
                <td>${cls.states.length} NOTICE states, each with an identical footnote</td>
                <td>page ${sliceCount + 4}, as a list</td></tr>
            <tr><td>their footnotes</td><td class="num">${Math.round(cls.span.boiler[0])}&ndash;${Math.round(cls.span.boiler[1])}</td>
                <td>${cls.boiler.length} copies of one and the same text &mdash; half the width of the drawing</td>
                <td>page ${sliceCount + 4}, printed once</td></tr>
            <tr class="hot"><td>the finding</td><td class="num">${Math.round(cls.span.defect[0])}&ndash;${Math.round(cls.span.defect[1])}</td>
                <td>OperatorMismatch @6795:17 &mdash; the only defect in the whole scan</td>
                <td>page ${sliceCount + 3}, enlarged</td></tr>
            <tr class="hot"><td>its WHY note</td><td class="num">${Math.round(cls.span.why[0])}&ndash;${Math.round(cls.span.why[1])}</td>
                <td>the explanation &mdash; <b>${gapOrig.toLocaleString('en-US')} px away from the finding</b></td>
                <td>page ${sliceCount + 3}, enlarged</td></tr>
          </tbody>
        </table>
        <p class="lede">The strip above is the <em>real</em> diagram, scaled to
        ${(full.w / WC).toFixed(1)}:1 so that its whole width fits the page.
        It is a map, not a readable drawing &mdash; its text is far below print size.
        ${Math.round(full.w).toLocaleString('en-US')} px of diagram cannot be shown
        at 1:1 on ${Math.ceil(full.w / WC)} A4 pages; the previous edition squeezed it
        onto 13 sheets, which left every label at roughly 8&nbsp;px and put the one
        actionable finding (x&nbsp;${Math.round(cls.span.defect[0])}) on one sheet
        and the note explaining it (x&nbsp;${Math.round(cls.span.why[0])}) about
        nine sheets later. The next two pages give that finding at full size and
        the ${cls.states.length} notices as a list.</p>
      `, `Detail ${act.id} - ${act.path} - key map of the full diagram (${Math.round(full.w)} x ${Math.round(full.h)} px)`);

      // ---------- page 2: the actionable finding, enlarged (true crop)
      if (foc.ok) {
        const fid = 'detfoc_' + act.id;
        const norm = reIdSvg(normalizeSvg(foc.svg, foc.w, foc.h, 0, 0, foc.w, foc.h), fid, fid + '_p');
        await page.evaluate((html, w, h, cap) => {
          const doc = document.getElementById('doc');
          const p = document.createElement('div');
          p.className = 'page';
          const c = document.createElement('p');
          c.className = 'slice-cap';
          c.textContent = cap;
          const win = document.createElement('div');
          win.className = 'crop';
          const WC = 186 * 96 / 25.4, PAGE_H = 273 * 96 / 25.4;
          p.appendChild(c);
          doc.appendChild(p);
          const capH = c.getBoundingClientRect().height +
            parseFloat(getComputedStyle(c).marginBottom || 0);
          const HC = PAGE_H - capH;
          const scale = Math.min(WC / w, HC / h);
          win.style.width = WC + 'px'; win.style.height = HC + 'px';
          const holder = document.createElement('div');
          holder.className = 'holder';
          holder.style.transform = `scale(${scale})`;
          holder.innerHTML = html;
          win.appendChild(holder);
          p.appendChild(win);
          doc.appendChild(p);
        }, norm, foc.w, foc.h,
          `Detail ${act.id} - the one actionable finding, enlarged (real render, ${Math.round(foc.w)} x ${Math.round(foc.h)} px)`);
        console.log(`detail ${act.id}: key map ${Math.round(full.w)}x${Math.round(full.h)},` +
          ` focused ${Math.round(foc.w)}x${Math.round(foc.h)}`);
      }

      // ---------- page 3: the notices of this file as a list
      const rows = act.notices.map((n) => {
        const mm = /^(NOTICE \u2014 )?([A-Za-z]+)( @([\d:]+))? \u2014 (.*)$/.exec(n.msg);
        const kind = mm ? mm[2] : 'NOTICE';
        const loc = mm && mm[4] ? mm[4] : '';
        const text = mm ? mm[5] : n.msg;
        return `<tr><td class="mono">${esc(n.id)}</td><td>${esc(kind)}</td>` +
          `<td class="mono">${esc(loc)}</td><td>${esc(text)}</td></tr>`;
      }).join('');
      // the shared boilerplate, printed once instead of 27 times
      let boiler = '';
      for (let i = 0; i < act.lines.length; i++) {
        if (/^\s*note right of f98_n0\s*$/.test(act.lines[i])) {
          const buf = [];
          for (let j = i + 1; j < act.lines.length && !/^\s*end note\s*$/.test(act.lines[j]); j++) {
            buf.push(act.lines[j].trim());
          }
          boiler = buf.join(' ');
          break;
        }
      }
      await page.evaluate((html, cap) => {
        const doc = document.getElementById('doc');
        const p = document.createElement('div');
        p.className = 'page flow';
        const c = document.createElement('p');
        c.className = 'slice-cap';
        c.textContent = cap;
        const box = document.createElement('div');
        box.innerHTML = html;
        p.appendChild(c);
        while (box.firstChild) p.appendChild(box.firstChild);
        doc.appendChild(p);
      }, `
        <h3 class="appx">Detail ${act.id} &mdash; the ${act.notices.length} NOTICE states of this file</h3>
        <p class="lede">In the source diagram every one of these ${act.notices.length} states
        carries the same footnote, printed ${act.notices.length} times side by side.
        The text is reproduced once, below the table, and the states are listed
        here instead of being drawn ${act.notices.length} times.</p>
        <blockquote class="boiler">${esc(boiler)}</blockquote>
        <table class="data notices">
          <thead><tr><th>state</th><th>kind</th><th>loc</th><th>message</th></tr></thead>
          <tbody>${rows}</tbody>
        </table>
      `, `Detail ${act.id} - ${act.path} - notice list`);

      await page.evaluate(() => {
        const el = document.getElementById('cropcount');
        if (el) el.textContent = '3 (key map, enlarged finding, notice list)';
      });
    }
  }

  // ---- append the data tables last
  await page.evaluate((ftab, ntab) => {
    const doc = document.getElementById('doc');
    const tmp = document.createElement('div');
    tmp.innerHTML = ftab + ntab;
    while (tmp.firstChild) doc.appendChild(tmp.firstChild);
  }, fileTableHtml(), noticeTableHtml());

  // ---- write the PDF
  const stats = await page.evaluate(() => {
    const pages = [...document.querySelectorAll('.page')];
    // A page whose content is taller than one sheet will spill onto a second
    // blank sheet. Detect that here rather than after the PDF exists.
    const spills = [];
    pages.forEach((p, i) => {
      const isFlow = p.classList.contains('flow');
      if (isFlow) return;
      if (p.scrollHeight > p.clientHeight + 1) spills.push({ i: i + 1, h: p.scrollHeight, c: p.clientHeight });
    });
    return { pages: pages.length, height: document.body.scrollHeight, spills };
  });
  console.log('print doc:', JSON.stringify(stats));
  if (stats.spills.length) {
    console.log('WARNING: pages that overflow onto a second sheet: ' +
      stats.spills.map((s) => `${s.i}(${s.h}>${s.c})`).join(' '));
  }

  await page.pdf({
    path: OUT_PDF,
    format: 'A4',
    printBackground: true,
    margin: { top: '12mm', bottom: '12mm', left: '12mm', right: '12mm' },
  });
  console.log('wrote', OUT_PDF, fs.statSync(OUT_PDF).size, 'bytes');
  await browser.close();
})().catch((e) => { console.error('HARNESS ERROR', e); process.exit(1); });
