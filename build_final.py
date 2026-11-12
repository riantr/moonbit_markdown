#!/usr/bin/env python3
"""Build the final self-contained HTML5 page for the Mermaid state diagram.

Architecture
------------
The source diagram is 21k lines / 3,254 states / 2,371 notes. Two hard limits
shaped this design, both measured rather than assumed:

1. dagre (mermaid's layout engine) CRASHES on this graph:
   "Cannot set properties of undefined (setting 'order')" in
   dagre/order/index.js assignOrder(). It is a compound-graph ordering bug
   that mermaid's note nodes trigger. Measured threshold: <=30 files render,
   >=40 files crash. So one monolithic SVG is not achievable.
2. A monolithic SVG would be ~129 MB even if it worked (120.8 MB detail +
   8.1 MB overview) - unusable in a browser.

So the page renders client-side with mermaid.min.js inlined, splitting the
source into (a) a flat 221-node overview and (b) 221 per-file composite
sub-diagrams, each of which dagre lays out fine. Everything ships in ONE
html file: no network, no sidecar assets.

The page body is a plain template (not an f-string) so that JS/CSS braces and
backslashes pass through verbatim; only __PLACEHOLDER__ tokens are substituted.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

MERMAID_MIN = Path(
    r"C:\Users\hp\AppData\Roaming\npm\node_modules\@mermaid-js\mermaid-cli"
    r"\node_modules\mermaid\dist\mermaid.min.js"
)


def parse_header(lines: list[str]) -> dict[str, str]:
    """The %% header packs several key=value pairs onto one line, e.g.

        %% files=221 parsed=221 partial=0 actionable=1 notices=2215 ...

    so each line must be split on whitespace before the pairs are read.
    """
    meta: dict[str, str] = {}
    for L in lines:
        s = L.strip()
        if not s.startswith("%%"):
            continue
        body = s.lstrip("%").strip()
        for pair in body.split():
            if "=" not in pair:
                continue
            k, _, v = pair.partition("=")
            meta.setdefault(k, v.strip())
    return meta


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mmd", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    mmd_path = Path(args.mmd)
    out_path = Path(args.out)

    source = mmd_path.read_text(encoding="utf-8")
    mermaid_js = MERMAID_MIN.read_text(encoding="utf-8")

    # Safety: inlined <script> bodies must not contain a closing tag.
    for name, blob in (("mermaid.min.js", mermaid_js), ("diagram source", source)):
        if "</script" in blob.lower():
            print(f"ERROR: {name} contains '</script' - cannot inline safely", file=sys.stderr)
            return 2

    meta = parse_header(source.splitlines())
    meta_json = json.dumps(meta, ensure_ascii=False)

    page = TEMPLATE
    for token, value in (
        ("__META_JSON__", meta_json),
        ("__DIAGRAM_SOURCE__", source),
        ("__MERMAID_JS__", mermaid_js),
        ("__VERSION__", meta.get("version", "")),
        ("__MOONBIT__", meta.get("moonbit", "")),
        ("__SCANNED_AT__", meta.get("scanned_at", "")),
        ("__TARGET__", meta.get("target", "")),
        ("__FILE_COUNT__", meta.get("files", "0")),
        ("__NOTICE_COUNT__", meta.get("notices", "0")),
        ("__ACTIONABLE_COUNT__", meta.get("actionable", "0")),
    ):
        page = page.replace(token, value)

    out_path.write_text(page, encoding="utf-8")
    print(f"wrote {out_path} ({out_path.stat().st_size / 1048576:.2f} MB)")
    print(f"  meta: {meta}")
    return 0


TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>moonbit_doubleML &mdash; Mermaid state diagram (HTML5 render)</title>
<style>
  :root {
    --bg:#0d1117; --panel:#161b22; --panel-2:#1c2129; --line:#2a313c;
    --fg:#e6edf3; --muted:#8b949e; --accent:#58a6ff; --accent-2:#3fb950;
    --warn:#d29922; --danger:#f85149;
  }
  * { box-sizing:border-box; }
  html,body { margin:0; background:var(--bg); color:var(--fg);
    font:14px/1.55 "Segoe UI",system-ui,-apple-system,"Helvetica Neue",Arial,sans-serif; }
  header { padding:15px 20px 12px; background:var(--panel); border-bottom:1px solid var(--line); }
  h1 { margin:0 0 3px; font-size:18px; font-weight:650; }
  h1 .badge { font-size:11px; color:var(--accent-2); border:1px solid var(--accent-2);
    border-radius:999px; padding:2px 9px; margin-left:9px; vertical-align:middle;
    background:rgba(63,185,80,.10); }
  .sub { color:var(--muted); font-size:12.5px; }
  .sub code { background:var(--panel-2); padding:1px 5px; border-radius:4px; font-size:12px; }
  .stats { display:flex; flex-wrap:wrap; gap:8px; margin-top:11px; }
  .stat { background:var(--panel-2); border:1px solid var(--line); border-radius:8px; padding:6px 12px; min-width:88px; }
  .stat-v { display:block; font-size:16px; font-weight:650; font-variant-numeric:tabular-nums; }
  .stat-k { display:block; font-size:10px; text-transform:uppercase; letter-spacing:.6px; color:var(--muted); }
  .stat.hot .stat-v { color:var(--warn); }
  main { display:grid; grid-template-columns:332px 1fr; height:calc(100vh - 128px); }
  aside { border-right:1px solid var(--line); background:var(--panel); overflow:auto; }
  .card { padding:11px 14px; border-bottom:1px solid var(--line); }
  .card h3 { margin:0 0 8px; font-size:11px; text-transform:uppercase; letter-spacing:.7px; color:var(--muted); }
  .muted { color:var(--muted); }
  input[type=search],textarea { width:100%; background:var(--panel-2); color:var(--fg);
    border:1px solid var(--line); border-radius:7px; padding:7px 10px; font:inherit; font-size:13px; }
  input:focus,textarea:focus { outline:none; border-color:var(--accent); }
  #filelist { max-height:34vh; overflow:auto; border-top:1px solid var(--line); }
  .fitem { display:flex; align-items:center; gap:7px; padding:5px 14px; cursor:pointer;
    border-left:2px solid transparent; font-size:12.5px; }
  .fitem:hover { background:var(--panel-2); }
  .fitem.sel { background:var(--panel-2); border-left-color:var(--accent); }
  .fitem .fname { flex:1 1 auto; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .fitem .fmeta { color:var(--muted); font-size:11px; font-variant-numeric:tabular-nums; white-space:nowrap; }
  .fitem.hot .fmeta { color:var(--warn); }
  .section { position:relative; overflow:hidden; background:
      radial-gradient(circle at 1px 1px, #1b2129 1px, transparent 0) 0 0/22px 22px, var(--bg); }
  .tabbar { position:absolute; top:0; left:0; right:0; z-index:6; display:flex; gap:5px;
    padding:9px 14px; background:linear-gradient(var(--panel) 72%, transparent); }
  .tabbar button { background:var(--panel-2); color:var(--fg); border:1px solid var(--line);
    border-radius:7px; padding:5px 13px; font:inherit; font-size:12.5px; cursor:pointer; }
  .tabbar button.on { border-color:var(--accent); color:var(--accent); }
  .tabbar .spacer { flex:1 1 auto; }
  .toolbar { display:flex; gap:5px; }
  .toolbar button { background:var(--panel-2); color:var(--fg); border:1px solid var(--line);
    border-radius:6px; padding:4px 10px; font:inherit; font-size:12px; cursor:pointer; }
  .toolbar button:hover { border-color:var(--accent); color:var(--accent); }
  .viewport { position:absolute; inset:44px 0 0 0; overflow:hidden; cursor:grab; }
  .viewport.drag { cursor:grabbing; }
  .viewport svg { position:absolute; top:0; left:0; transform-origin:0 0; }
  .viewport svg * { shape-rendering:geometricPrecision; }
  .viewport svg.hide-text .label,
  .viewport svg.hide-text .edgeLabel,
  .viewport svg.hide-text foreignObject { opacity:0; }
  .readout { position:absolute; bottom:11px; left:14px; z-index:5; color:var(--muted); font-size:11.5px;
    background:rgba(22,27,34,.92); border:1px solid var(--line); border-radius:7px; padding:4px 10px;
    font-variant-numeric:tabular-nums; }
  .hint { position:absolute; bottom:11px; right:14px; z-index:5; color:var(--muted); font-size:11px;
    background:rgba(22,27,34,.92); border:1px solid var(--line); border-radius:7px; padding:4px 10px; }
  .panel { position:absolute; top:44px; right:14px; width:352px; max-height:calc(100% - 96px);
    overflow:auto; z-index:5; background:rgba(22,27,34,.97); border:1px solid var(--line);
    border-radius:9px; padding:10px 12px; font-size:12px; display:none; }
  .panel.show { display:block; }
  .panel h4 { margin:0 0 8px; font-size:11px; text-transform:uppercase; letter-spacing:.6px; color:var(--muted); }
  .nrow { padding:5px 0; border-top:1px solid var(--line); }
  .nrow:first-of-type { border-top:none; }
  .nrow .nloc { color:var(--accent); font-family:Consolas,ui-monospace,monospace; font-size:11px; }
  .nrow .nkind { color:var(--warn); }
  .nrow.act .nkind { color:var(--danger); }
  .empty { color:var(--muted); font-size:12px; padding:4px 0; }
  .status { position:absolute; top:52px; left:50%; transform:translateX(-50%); z-index:9;
    background:var(--panel-2); border:1px solid var(--line); color:var(--muted); padding:6px 14px;
    border-radius:8px; font-size:12px; display:none; }
  .status.show { display:block; }
  .status.err { background:var(--danger); border-color:var(--danger); color:#fff; }
  #srctext { width:100%; height:calc(100% - 40px); background:var(--panel); color:var(--fg);
    border:1px solid var(--line); border-radius:8px; padding:12px; font:12px/1.5 Consolas,ui-monospace,monospace;
    resize:none; white-space:pre; overflow:auto; }
  @media (max-width:980px) { main { grid-template-columns:1fr; } aside { display:none; } }
</style>
</head>
<body>
<header>
  <h1>riantr/moonbit_doubleML<span class="badge">Mermaid &rarr; HTML5</span></h1>
  <div class="sub">
    <code>stateDiagram-v2</code> &middot; version __VERSION__ &middot;
    moonbit __MOONBIT__ &middot; scanned __SCANNED_AT__ &middot;
    __FILE_COUNT__ files scanned &middot; __NOTICE_COUNT__ notices &middot;
    __ACTIONABLE_COUNT__ actionable
  </div>
  <div class="stats" id="stats"></div>
</header>
<main>
  <aside>
    <div class="card">
      <h3>Find a file</h3>
      <input type="search" id="fsearch" placeholder="filter by path or name&hellip;" autocomplete="off">
    </div>
    <div id="filelist"></div>
    <div class="card">
      <h3>Notices</h3>
      <input type="search" id="nsearch" placeholder="filter notices&hellip;" autocomplete="off">
      <div id="noticelist" style="max-height:26vh;overflow:auto;margin-top:8px"></div>
    </div>
    <div class="card" id="metacard"></div>
  </aside>
  <section class="section">
    <div class="tabbar">
      <button id="tab-overview" class="on">Overview</button>
      <button id="tab-detail">File detail</button>
      <button id="tab-source">Source</button>
      <span class="spacer"></span>
      <div class="toolbar">
        <button id="zoom-out" title="Zoom out">&minus;</button>
        <button id="zoom-in" title="Zoom in">+</button>
        <button id="zoom-fit" title="Fit to screen">Fit</button>
        <button id="zoom-1" title="Actual size">1:1</button>
        <button id="toggle-text" title="Show or hide diagram text">Text</button>
        <button id="toggle-panel" title="Show or hide the findings panel">Notes</button>
      </div>
    </div>
    <div class="viewport" id="viewport"></div>
    <textarea id="srctext" spellcheck="false" style="display:none"></textarea>
    <div class="panel" id="noticepanel"></div>
    <div class="status" id="status"></div>
    <div class="readout" id="readout">100%</div>
    <div class="hint">drag to pan &middot; wheel to zoom</div>
  </section>
</main>

<script type="application/json" id="meta">__META_JSON__</script>
<script type="text/plain" id="diagram-src">__DIAGRAM_SOURCE__</script>
<script>__MERMAID_JS__</script>
<script>
(function () {
  'use strict';
  var META = JSON.parse(document.getElementById('meta').textContent);
  var SRC = document.getElementById('diagram-src').textContent;

  // ---------------------------------------------------------------- split
  // The source is a flat list of per-file composite states hanging off `scan`:
  //   scan --> fN : <label>
  //   state "fN - <path>" as fN { ... }
  var EM = String.fromCharCode(8212); // em dash
  // Pipeline stages belong to the trust chain, not to the finding set.
  var STAGE_RE = /^(lexed|inspection [123]\/3)/;
  var lines = SRC.split(/\r?\n/);
  var firstEdge = -1;
  for (var i = 0; i < lines.length; i++) {
    if (/^ {4}scan --> f\d+ :/.test(lines[i])) { firstEdge = i; break; }
  }
  var blocks = [], cur = null;
  for (var j = firstEdge; j < lines.length; j++) {
    var L = lines[j];
    var m = /^ {4}scan --> (f\d+) :/.exec(L);
    if (m) { cur = { id: m[1], lines: [L] }; blocks.push(cur); continue; }
    if (cur) {
      cur.lines.push(L);
      if (/^ {4}\}$/.test(L)) cur = null;
    }
  }

  var files = blocks.map(function (b) {
    var path = '', edgeLabel = '';
    for (var k = 0; k < b.lines.length; k++) {
      var pm = new RegExp('^ {4}state "f\\d+ ' + EM + ' (.*)" as f\\d+ \\{$').exec(b.lines[k]);
      if (pm) { path = pm[1]; }
      if (k === 0) edgeLabel = b.lines[0].split(':').slice(1).join(':').trim();
    }
    var acts = edgeLabel.match(/(\d+) actionable/);
    var ntcs = edgeLabel.match(/(\d+) notice\(s\)/);
    var notices = [], others = [], stages = [];
    b.lines.forEach(function (L2) {
      var sm = /^\s+state "(.*?)" as ([A-Za-z0-9_]+)\s*$/.exec(L2);
      if (!sm) return;
      var msg = sm[1], sid = sm[2];
      if (msg.indexOf('NOTICE ' + EM + ' ') === 0) { notices.push({ id: sid, msg: msg }); return; }
      // The per-file composite header itself ("fN - <path>") is not a finding.
      if (new RegExp('^f\\d+ ' + EM + ' ').test(msg)) return;
      // Pipeline stages are part of the trust chain, not findings: they are
      // "lexed" and "inspection 1/3..3/3". Only genuine defects land here.
      if (STAGE_RE.test(msg)) { stages.push({ id: sid, msg: msg }); return; }
      others.push({ id: sid, msg: msg });
    });
    return {
      id: b.id,
      path: path,
      name: path ? path.split('/').pop() : b.id,
      actionable: acts ? +acts[1] : 0,
      noticeCount: ntcs ? +ntcs[1] : 0,
      notices: notices,
      others: others,
      stages: stages,
      src: ['stateDiagram-v2', '    direction TB'].concat(b.lines).join('\n')
    };
  });

  // ---------------------------------------------------------------- state
  var vp = document.getElementById('viewport');
  var readout = document.getElementById('readout');
  var noticePanel = document.getElementById('noticepanel');
  var statusEl = document.getElementById('status');
  var srcText = document.getElementById('srctext');
  var svg = null, view = { x: 0, y: 0, k: 1 }, W = 1, H = 1, mode = 'overview';
  var seq = 0;

  function status(msg, isErr) {
    statusEl.textContent = msg || '';
    statusEl.className = 'status' + (msg ? ' show' : '') + (isErr ? ' err' : '');
    if (msg && !isErr) setTimeout(function () { statusEl.className = 'status'; }, 1200);
  }
  function apply() {
    if (!svg) return;
    svg.style.transform = 'translate(' + view.x + 'px,' + view.y + 'px) scale(' + view.k + ')';
    readout.textContent = Math.round(view.k * 100) + '%';
  }
  function fitTo(mode) {
    // 'all'    - whole diagram inside the viewport (may be tiny for wide graphs)
    // 'width'  - fill the width; useful for the tall LR overview column
    // 'height' - fill the height; keeps a file's trust chain fully visible
    var r = vp.getBoundingClientRect();
    var sx = r.width / W, sy = r.height / H, k;
    if (mode === 'width') k = sx;
    else if (mode === 'height') k = sy;
    else k = Math.min(sx, sy);
    k = Math.max(0.02, Math.min(4, k));
    view.k = k;
    view.x = (r.width - W * k) / 2;
    view.y = (r.height - H * k) / 2;
    if (mode === 'width') view.y = 0;   // overview reads top-to-bottom
    // When the diagram is wider than the viewport, centring would hide the
    // start of the trust chain; anchor it to the left edge instead.
    if (W * k > r.width) view.x = 0;
    apply();
  }
  function zoomAt(cx, cy, factor) {
    var k2 = Math.max(0.02, Math.min(10, view.k * factor));
    view.x = cx - (cx - view.x) * (k2 / view.k);
    view.y = cy - (cy - view.y) * (k2 / view.k);
    view.k = k2; apply();
  }
  function mount(el, fitMode) {
    vp.innerHTML = '';
    vp.appendChild(el);
    svg = el;
    svg.removeAttribute('width'); svg.removeAttribute('height');
    svg.style.width = W + 'px'; svg.style.height = H + 'px';
    apply();
    // always start from a fitted view, not the raw 1:1 origin
    fitTo(fitMode || 'all');
  }
  function setViewBox(el) {
    var vb = (el.getAttribute('viewBox') || '').split(/[ ,]+/).map(Number);
    W = (vb.length === 4 && vb[2] > 0) ? vb[2] : (el.getBoundingClientRect().width || 1000);
    H = (vb.length === 4 && vb[3] > 0) ? vb[3] : (el.getBoundingClientRect().height || 600);
  }

  // ---------------------------------------------------------------- render
  function render(src, label, fitMode) {
    status('rendering ' + label + '...');
    var id = 'dgm_' + (++seq);
    return window.mermaid.render(id, src).then(function (res) {
      var holder = document.createElement('div');
      holder.innerHTML = res.svg;
      var el = holder.querySelector('svg');
      if (!el) throw new Error('no svg produced');
      setViewBox(el);
      mount(el, fitMode);
      status('');
    }).catch(function (e) {
      status('render failed: ' + ((e && e.message) || e), true);
      throw e;
    });
  }

  function overviewSrc() {
    // LR keeps the 221 files in one tall column (911 x 25160 px) instead of a
    // single unreadable 115,010 px row, and reads top-to-bottom like a list.
    var out = ['stateDiagram-v2', '    direction LR'];
    files.forEach(function (f) {
      out.push('    state "' + f.id + ' ' + EM + ' ' + f.path + '" as ' + f.id);
    });
    out.push('    state "scan ' + EM + ' ' + (META.target || '') + '" as scan');
    files.forEach(function (f) {
      out.push('    scan --> ' + f.id + ' : ' + f.actionable + ' actionable, ' +
               f.noticeCount + ' notice(s), parsed');
    });
    return out.join('\n');
  }

  function setTab(id) {
    ['tab-overview', 'tab-detail', 'tab-source'].forEach(function (t) {
      document.getElementById(t).className = (t === id) ? 'on' : '';
    });
  }
  function showOverview() {
    mode = 'overview';
    noticePanel.className = 'panel';
    srcText.style.display = 'none';
    vp.style.display = '';
    setTab('tab-overview');
    return render(overviewSrc(), 'overview', 'width').then(function () {
      // make each file node in the overview clickable -> open its detail view
      var nodes = svg.querySelectorAll('g.node');
      for (var i = 0; i < nodes.length; i++) {
        (function (el) {
          var id = (el.getAttribute('id') || '');
          var mm = /state-(f\d+)-/.exec(id);
          if (!mm) return;
          var fid = mm[1];
          if (!files.some(function (f) { return f.id === fid; })) return;
          el.style.cursor = 'pointer';
          el.addEventListener('click', function () {
            var row = document.querySelector('.fitem[data-id="' + fid + '"]');
            for (var k = 0; k < items.length; k++) items[k].classList.remove('sel');
            if (row) { row.classList.add('sel'); row.scrollIntoView({ block: 'nearest' }); }
            showDetail(fid);
          });
        })(nodes[i]);
      }
    });
  }
  function showDetail(fid) {
    mode = 'detail';
    srcText.style.display = 'none';
    vp.style.display = '';
    setTab('tab-detail');
    var f = files.filter(function (x) { return x.id === fid; })[0];
    if (!f) return Promise.resolve();
    // 'height' keeps the file's full trust chain on screen; the notice fan-out
    // extends far to the right and is reached by panning.
    return render(f.src, f.id, 'height').then(function () { renderNoticePanel(f); });
  }
  function showSource() {
    mode = 'source';
    setTab('tab-source');
    noticePanel.className = 'panel';
    vp.style.display = 'none';
    srcText.style.display = '';
    if (!srcText.value) srcText.value = SRC;
    svg = null;
  }

  function renderNoticePanel(f) {
    var html = '<h4>' + f.id + ' &middot; ' + f.path + '</h4>';
    html += '<div class="empty">' + f.noticeCount + ' notice(s) declared, ' +
            f.notices.length + ' notice node(s) drawn' +
            (f.noticeCount !== f.notices.length
              ? ' <span class="muted">(the source caps notice nodes per file)</span>' : '') +
            (f.others.length ? ', ' + f.others.length + ' actionable finding(s)' : '') + '</div>';
    f.others.forEach(function (o) {
      html += '<div class="nrow act"><span class="nkind">FINDING</span> <span class="nloc">' +
              o.id + '</span><br>' + o.msg + '</div>';
    });
    f.notices.forEach(function (n) {
      html += '<div class="nrow"><span class="nkind">NOTICE</span> <span class="nloc">' +
              n.id + '</span><br>' + n.msg + '</div>';
    });
    if (!f.notices.length && !f.others.length) html += '<div class="empty">No findings.</div>';
    noticePanel.innerHTML = html;
    noticePanel.className = 'panel show';
  }

  // ---------------------------------------------------------------- chrome
  var statsEl = document.getElementById('stats');
  var drawnNotices = files.reduce(function (a, f) { return a + f.notices.length; }, 0);
  var drawnFindings = files.reduce(function (a, f) { return a + f.others.length; }, 0);
  [
    ['Files', files.length],
    ['Parsed', META.parsed || 0],
    ['Actionable', META.actionable || 0],
    ['Notices', META.notices || 0],
    ['Notice nodes drawn', drawnNotices],
    ['Actionable drawn', drawnFindings],
    ['Total findings', META.total || 0]
  ].forEach(function (kv) {
    var d = document.createElement('div');
    d.className = 'stat' + (kv[0] === 'Actionable' && kv[1] !== '0' ? ' hot' : '');
    d.innerHTML = '<span class="stat-v"></span><span class="stat-k"></span>';
    d.querySelector('.stat-v').textContent = kv[1];
    d.querySelector('.stat-k').textContent = kv[0];
    statsEl.appendChild(d);
  });

  var metaCard = document.getElementById('metacard');
  metaCard.innerHTML = '<h3>Diagram metadata</h3><table style="width:100%;font-size:12.5px;border-collapse:collapse">' +
    Object.keys(META).map(function (k) {
      return '<tr><td style="color:var(--muted);padding:2px 8px 2px 0;white-space:nowrap;vertical-align:top">' +
             k + '</td><td style="padding:2px 0;word-break:break-all">' + META[k] + '</td></tr>';
    }).join('') + '</table>';

  // Expose the parsed model for automated verification and for embedding.
  window.__files = files;
  window.__meta = META;

  var fl = document.getElementById('filelist');
  var items = files.map(function (f) {
    var el = document.createElement('div');
    el.className = 'fitem' + (f.actionable ? ' hot' : '');
    el.dataset.id = f.id;
    el.innerHTML = '<span class="fname"></span><span class="fmeta"></span>';
    el.querySelector('.fname').textContent = f.name;
    el.querySelector('.fmeta').textContent = f.actionable
      ? f.actionable + ' act / ' + f.noticeCount + ' ntc'
      : f.noticeCount + ' ntc';
    el.title = f.path;
    el.onclick = function () {
      for (var i = 0; i < items.length; i++) items[i].classList.remove('sel');
      el.classList.add('sel');
      showDetail(f.id);
    };
    fl.appendChild(el);
    return el;
  });

  document.getElementById('fsearch').addEventListener('input', function () {
    var q = this.value.toLowerCase().trim();
    for (var i = 0; i < items.length; i++) {
      var f = files[i];
      var hay = (f.path + ' ' + f.name + ' ' + f.id).toLowerCase();
      items[i].style.display = (!q || hay.indexOf(q) >= 0) ? '' : 'none';
    }
  });

  var nl = document.getElementById('noticelist');
  function renderNotices(q) {
    nl.innerHTML = '';
    q = (q || '').toLowerCase().trim();
    var shown = 0;
    files.forEach(function (f) {
      f.notices.forEach(function (n) {
        if (q && (n.msg + ' ' + f.id + ' ' + f.path).toLowerCase().indexOf(q) < 0) return;
        shown++;
        var row = document.createElement('div');
        row.className = 'nrow';
        row.style.cursor = 'pointer';
        row.innerHTML = '<span class="nkind">NOTICE</span> <span class="nloc">' + f.id +
                        ' / ' + n.id + '</span><br>';
        var t = document.createElement('span');
        t.textContent = n.msg;
        row.appendChild(t);
        row.onclick = function () {
          var el = document.querySelector('.fitem[data-id="' + f.id + '"]');
          for (var i = 0; i < items.length; i++) items[i].classList.remove('sel');
          if (el) el.classList.add('sel');
          showDetail(f.id);
        };
        nl.appendChild(row);
      });
    });
    if (!shown) nl.innerHTML = '<div class="empty">No matching notices.</div>';
  }
  document.getElementById('nsearch').addEventListener('input', function () { renderNotices(this.value); });
  renderNotices('');

  document.getElementById('tab-overview').onclick = showOverview;
  document.getElementById('tab-detail').onclick = function () {
    var sel = document.querySelector('.fitem.sel') || items[0];
    if (sel) {
      if (!sel.classList.contains('sel')) sel.classList.add('sel');
      showDetail(sel.dataset.id);
    }
  };
  document.getElementById('tab-source').onclick = showSource;

  document.getElementById('zoom-in').onclick = function () {
    var r = vp.getBoundingClientRect(); zoomAt(r.width / 2, r.height / 2, 1.25);
  };
  document.getElementById('zoom-out').onclick = function () {
    var r = vp.getBoundingClientRect(); zoomAt(r.width / 2, r.height / 2, 0.8);
  };
  document.getElementById('zoom-fit').onclick = function () { if (svg) fitTo('all'); };
  document.getElementById('zoom-1').onclick = function () {
    if (!svg) return;
    var r = vp.getBoundingClientRect();
    view.k = 1; view.x = (r.width - W) / 2; view.y = (r.height - H) / 2; apply();
  };
  document.getElementById('toggle-text').onclick = function () {
    if (!svg) return;
    var hidden = svg.classList.contains('hide-text');
    if (hidden) { svg.classList.remove('hide-text'); this.textContent = 'Text'; }
    else { svg.classList.add('hide-text'); this.textContent = 'Labels'; }
  };
  document.getElementById('toggle-panel').onclick = function () {
    var hidden = noticePanel.className.indexOf('show') >= 0;
    noticePanel.className = hidden ? 'panel' : 'panel show';
    this.textContent = hidden ? 'Notes' : 'Hide notes';
  };

  vp.addEventListener('wheel', function (e) {
    e.preventDefault();
    var r = vp.getBoundingClientRect();
    zoomAt(e.clientX - r.left, e.clientY - r.top, e.deltaY < 0 ? 1.12 : 0.89);
  }, { passive: false });

  var dragging = false, sx = 0, sy = 0, ox = 0, oy = 0;
  vp.addEventListener('pointerdown', function (e) {
    dragging = true; sx = e.clientX; sy = e.clientY; ox = view.x; oy = view.y;
    vp.classList.add('drag');
    try { vp.setPointerCapture(e.pointerId); } catch (err) {}
  });
  vp.addEventListener('pointermove', function (e) {
    if (!dragging) return;
    view.x = ox + (e.clientX - sx); view.y = oy + (e.clientY - sy); apply();
  });
  ['pointerup', 'pointercancel'].forEach(function (ev) {
    vp.addEventListener(ev, function (e) {
      dragging = false; vp.classList.remove('drag');
      try { vp.releasePointerCapture(e.pointerId); } catch (err) {}
    });
  });

  window.addEventListener('resize', function () { if (svg) fitTo(mode === 'overview' ? 'width' : 'height'); });

  window.mermaid.initialize({
    startOnLoad: false,
    maxTextSize: 20000000,
    maxEdges: 500000,
    theme: 'default'
  });

  showOverview();
})();
</script>
</body>
</html>
"""


if __name__ == "__main__":
    sys.exit(main())
