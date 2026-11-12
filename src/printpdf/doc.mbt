///|
/// Assembling the printable document.

///|
/// The page order is fixed: cover, overview, detail, appendices. Every page
/// is A4 portrait with 12 mm margins, which leaves 186 x 273 mm of usable
/// area; the caption above a drawing is measured at run time, because the
/// page overflows onto a second, blank sheet otherwise.

///|
pub using @text {chars, text, trimmed}

///|
/// The printable stylesheet.
///
pub const PRINT_CSS : String = "@page{size:A4 portrait;margin:12mm}*{box-sizing:border-box}body{margin:0;background:#fff;color:#111;font:10.5pt/1.45 'Segoe UI',Arial,Helvetica,sans-serif}.page{width:186mm;height:273mm;page-break-after:always;break-after:page;position:relative;overflow:hidden;padding:0}.page:last-child{page-break-after:auto;break-after:auto}.page.flow{height:auto;min-height:0}h1{font-size:24pt;margin:0 0 4pt;letter-spacing:-.3pt}h2{font-size:12pt;font-weight:500;color:#555;margin:0 0 10pt}h3{font-size:12pt;margin:16pt 0 5pt}h3.appx{margin:0 0 8pt}code,.mono{font-family:Consolas,'Courier New',monospace;font-size:9pt}.rule{height:2px;background:#111;margin:0 0 12pt}table.kv{border-collapse:collapse;width:100%;margin-bottom:6pt}table.kv th{text-align:left;width:26%;color:#555;font-weight:500;padding:1.5pt 8pt 1.5pt 0;vertical-align:top}table.kv td{padding:1.5pt 0}table.data{border-collapse:collapse;width:100%;font-size:8.6pt}table.data th{text-align:left;background:#ececec;border-bottom:1px solid #999;padding:3pt 5pt;font-weight:600}table.data td{border-bottom:1px solid #e2e2e2;padding:2.2pt 5pt;vertical-align:top}table.data tr{page-break-inside:avoid;break-inside:avoid}table.data thead{display:table-header-group}table.data td.num{text-align:right;font-variant-numeric:tabular-nums}table.data td.path{word-break:break-all}table.data tr.hot td{background:#fff6e0}table.notices td:nth-child(5){width:52%}.cover ul.toc,.cover ul.notes{padding-left:14pt;margin:4pt 0 0;font-size:9.6pt}.cover ul.notes li{margin:2pt 0}.cover p{font-size:9.8pt;margin:4pt 0}.lede{font-size:9.6pt;color:#444;margin:0 0 8pt}.crop{position:relative;overflow:hidden}.crop>.holder{position:absolute;left:0;top:0;transform-origin:0 0}.slice-cap{font-size:8.4pt;color:#666;margin:0 0 4pt;height:14pt}.km{position:relative;width:186mm;margin:0 0 7pt}.km-svg{position:relative;width:100%}.km-svg svg{display:block;width:100%;height:auto}.km-tick{position:absolute;top:0;width:1px;height:100%;background:#c9c9c9}.km-tick.hot{background:#c0392b;width:1.5px}.km-band{position:absolute;top:0;height:100%;background:rgba(70,110,190,.10);border-left:1px solid #7d9cc4;border-right:1px solid #7d9cc4}.km-labs{position:relative;height:11pt}.km-lab{position:absolute;top:0;font-size:6.2pt;font-weight:400;color:#666;transform:translateX(-50%);white-space:nowrap}.km-lab.hot{color:#c0392b;font-weight:700}.km-lab.band{color:#3c5f91}table.keymap-tbl{font-size:8.4pt;margin-bottom:7pt}table.keymap-tbl tr.hot td{background:#fff6e0}blockquote.boiler{margin:4pt 0 8pt;padding:5pt 8pt;background:#f5f5f5;border-left:3px solid #999;font-size:8.4pt;color:#333}"

///|
/// Escape text for HTML.
///
pub fn esc(s : String) -> String {
  let sb = StringBuilder()
  for c in s.iter() {
    match c {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '"' => sb.write_string("&quot;")
      '\'' => sb.write_string("&#39;")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// The cover page: the metadata, how to read the diagram, the actionable
/// findings, the contents and the notes on the rendering.
///
/// The notes are not decoration: they say where the source's own numbers
/// disagree with the drawing (the header claims more notices than the
/// generator drew) and what the layout had to do about it.
///
pub fn cover_html(
  d : @mermaid.Diagram,
  p : PrintPlan,
  m : Measurement,
) -> String {
  let sb = StringBuilder()
  let slice_count = p.slices.length()
  let file_count = d.files.length()
  let notices = @mermaid.drawn_notices(d)
  // the files whose drawn notice states are fewer than their edge label claims
  let mut capped = 0
  for f in d.files {
    if @mermaid.drawn_file_notices(f) < f.notice_count {
      capped += 1
    }
  }
  let (full_w, _) = full_size(m)
  sb.write_string("<div class=\"page cover\">\n")
  sb.write_string("<h1>")
  sb.write_string(esc(@mermaid.meta_of(d, "target")))
  sb.write_string(
    "</h1>\n<h2>Mermaid <code>stateDiagram-v2</code> &mdash; HTML5 render, printed to PDF</h2>\n",
  )
  sb.write_string("<div class=\"rule\"></div>\n<table class=\"kv\">\n")
  let rows = [
    ("target", "target"),
    ("version", "version"),
    ("moonbit", "moonbit"),
    ("scanned_at", "scanned at"),
    ("files", "files"),
    ("parsed", "parsed"),
    ("partial", "partial"),
    ("actionable", "actionable"),
    ("notices", "notices"),
    ("unreliable", "unreliable"),
    ("withheld", "withheld"),
    ("total", "total findings"),
  ]
  for r in rows {
    sb.write_string("<tr><th>")
    sb.write_string(r.1)
    sb.write_string("</th><td class=\"mono\">")
    sb.write_string(esc(@mermaid.meta_of(d, r.0)))
    sb.write_string("</td></tr>\n")
  }
  sb.write_string("</table>\n")
  sb.write_string("<h3>How to read this diagram</h3>\n")
  sb.write_string(
    "<p>The trust chain, not the counts, is the point. Each of the ",
  )
  sb.write_string(file_count.to_string())
  sb.write_string(
    " files is scanned by the same three inspections &mdash; <em>structural</em>, <em>type</em>, <em>behavioral</em> &mdash; after a lex pass. A file's findings hang off its <em>inspection 1/3 &mdash; structural</em> state.</p>\n",
  )
  sb.write_string(
    "<p>Nearly every finding is a <strong>NOTICE</strong>: a declaration form the analyzer does not model was read but not analysed. Notices are counted in <code>notices</code> and are <em>excluded</em> from <code>actionable</code>; they are not defects, even though they are drawn like them. Exactly <strong>",
  )
  sb.write_string(@mermaid.meta_of(d, "actionable"))
  sb.write_string("</strong> finding in this scan is a real defect:</p>\n")
  sb.write_string(
    "<table class=\"data\">\n<thead><tr><th>file</th><th>state</th><th>finding</th><th>path</th></tr></thead>\n<tbody>\n",
  )
  for f in d.files {
    for s in f.states {
      if @mermaid.is_notice(s.msg) ||
        @mermaid.is_stage(s.msg) ||
        @mermaid.is_file_label(f.id, s.msg) {
        continue
      }
      sb.write_string("<tr><td class=\"mono\">")
      sb.write_string(esc(f.id))
      sb.write_string("</td><td class=\"mono\">")
      sb.write_string(esc(s.id))
      sb.write_string("</td><td>")
      sb.write_string(esc(s.msg))
      sb.write_string("</td><td class=\"mono\">")
      sb.write_string(esc(f.path))
      sb.write_string("</td></tr>\n")
    }
  }
  sb.write_string("</tbody>\n</table>\n")
  sb.write_string("<h3>Contents</h3>\n<ul class=\"toc\">\n")
  sb.write_string(
    "<li><b>Overview</b> &mdash; the <code>scan</code> node and all ",
  )
  sb.write_string(file_count.to_string())
  sb.write_string(" files with their per-file finding counts, split across ")
  sb.write_string(slice_count.to_string())
  sb.write_string(" pages.</li>\n")
  sb.write_string("<li><b>Detail: ")
  sb.write_string(esc(p.detail_id))
  sb.write_string(
    "</b> &mdash; the one file with an actionable finding, in <span id=\"cropcount\">3</span> pages: a <b>key map</b> of the full diagram, the <b>actionable finding enlarged</b> from the real render, and the file's <b>notices as a list</b> with the shared footnote printed once.</li>\n",
  )
  sb.write_string("<li><b>Appendix A</b> &mdash; all ")
  sb.write_string(file_count.to_string())
  sb.write_string(" files, their paths and finding counts.</li>\n")
  sb.write_string("<li><b>Appendix B</b> &mdash; all ")
  sb.write_string(notices.to_string())
  sb.write_string(" notice states, with their source locations.</li>\n")
  sb.write_string("</ul>\n")
  sb.write_string("<h3>Notes on this rendering</h3>\n<ul class=\"notes\">\n")
  sb.write_string("<li>The source is ")
  sb.write_string(d.lines_total.to_string())
  sb.write_string(" lines with ")
  sb.write_string(@mermaid.drawn_states(d).to_string())
  sb.write_string(" states and ")
  sb.write_string(@mermaid.drawn_notes(d).to_string())
  sb.write_string(
    " notes. Mermaid's layout engine (dagre) cannot lay out this graph in one piece &mdash; it fails in <code>order/index.js</code> with <code>Cannot set properties of undefined (setting 'order')</code> once more than ~30 compound states carry notes.</li>\n",
  )
  sb.write_string("<li>")
  sb.write_string(esc(p.detail_id))
  sb.write_string(" is drawn as a ")
  sb.write_string(group(full_w.round().to_int()))
  sb.write_string("&nbsp;px wide strip whose ")
  sb.write_string(notices_of_detail(p).to_string())
  sb.write_string(
    " NOTICE states each carry the <em>same</em> footnote; sliced across pages it filled 13 sheets at roughly 8&nbsp;px type. The detail section prints a key map of the strip, the actionable finding enlarged from the real render, and the notices as a list &mdash; same content, readable size.</li>\n",
  )
  sb.write_string("<li>The header reports ")
  sb.write_string(@mermaid.meta_of(d, "notices"))
  sb.write_string(" notices, but the source draws ")
  sb.write_string(notices.to_string())
  sb.write_string(
    " notice <em>states</em>: the generator caps notice states at 40 per file, so ",
  )
  sb.write_string(capped.to_string())
  sb.write_string(" file")
  if capped == 1 {
    sb.write_string(" shows")
  } else {
    sb.write_string("s show")
  }
  sb.write_string(
    " fewer nodes than their edge label claims. This PDF reproduces the source as-is.</li>\n",
  )
  sb.write_string("<li>Per-file diagrams for the other ")
  sb.write_string((file_count - 1).to_string())
  sb.write_string(
    " files stay interactive in the HTML5 page; their complete notice data is in Appendix B.</li>\n",
  )
  sb.write_string("</ul>\n</div>\n")
  sb.to_string()
}

///|
/// How many NOTICE states the detailed file carries.
///
fn notices_of_detail(p : PrintPlan) -> Int32 {
  p.detail_notices
}

///|
/// Appendix A: every scanned file, its path and its counts.
///
pub fn file_table_html(d : @mermaid.Diagram) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "<div class=\"page flow\">\n<h3 class=\"appx\">Appendix A &mdash; all scanned files</h3>\n",
  )
  sb.write_string(
    "<table class=\"data\">\n<thead><tr><th>file</th><th>path</th><th class=\"num\">actionable</th>",
  )
  sb.write_string(
    "<th class=\"num\">notices (label)</th><th class=\"num\">notice states</th><th class=\"num\">findings</th></tr></thead>\n<tbody>\n",
  )
  for f in d.files {
    let notices = @mermaid.drawn_file_notices(f)
    let findings = @mermaid.drawn_file_findings(f)
    sb.write_string("<tr class=\"")
    if findings > 0 {
      sb.write_string("hot")
    }
    sb.write_string("\"><td class=\"mono\">")
    sb.write_string(esc(f.id))
    sb.write_string("</td><td class=\"mono path\">")
    sb.write_string(esc(f.path))
    sb.write_string("</td><td class=\"num\">")
    sb.write_string(f.actionable.to_string())
    sb.write_string("</td><td class=\"num\">")
    sb.write_string(f.notice_count.to_string())
    sb.write_string("</td><td class=\"num\">")
    sb.write_string(notices.to_string())
    sb.write_string("</td><td class=\"num\">")
    sb.write_string(findings.to_string())
    sb.write_string("</td></tr>\n")
  }
  sb.write_string("</tbody>\n</table>\n</div>\n")
  sb.to_string()
}

///|
/// Appendix B: every NOTICE state, with its source location.
///
pub fn notice_table_html(d : @mermaid.Diagram) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "<div class=\"page flow\">\n<h3 class=\"appx\">Appendix B &mdash; all ",
  )
  sb.write_string(@mermaid.drawn_notices(d).to_string())
  sb.write_string(" notice states</h3>\n")
  sb.write_string(
    "<p class=\"lede\">Every notice below is excluded from the <code>actionable</code> count. They are declaration forms the analyzer does not model, not defects.</p>\n",
  )
  sb.write_string(
    "<table class=\"data notices\">\n<thead><tr><th>file</th><th>state</th><th>kind</th><th>loc</th><th>message</th></tr></thead>\n<tbody>\n",
  )
  for f in d.files {
    for s in f.states {
      if !@mermaid.is_notice(s.msg) {
        continue
      }
      let kind = notice_kind(s.msg)
      let loc = notice_loc(s.msg)
      sb.write_string("<tr><td class=\"mono\">")
      sb.write_string(esc(f.id))
      sb.write_string("</td><td class=\"mono\">")
      sb.write_string(esc(s.id))
      sb.write_string("</td><td>")
      sb.write_string(esc(kind))
      sb.write_string("</td><td class=\"mono\">")
      sb.write_string(esc(loc))
      sb.write_string("</td><td>")
      sb.write_string(esc(notice_text(s.msg)))
      sb.write_string("</td></tr>\n")
    }
  }
  sb.write_string("</tbody>\n</table>\n</div>\n")
  sb.to_string()
}

///|
/// The kind of a NOTICE message, e.g. `ParseError`.
///
pub fn notice_kind(msg : String) -> String {
  let rest = strip_notice_prefix(msg)
  let mut end = 0
  let cs = chars(rest)
  while end < cs.length() && cs[end] != ' ' {
    end += 1
  }
  text(cs, 0, end)
}

///|
/// The prefix a NOTICE message carries: `NOTICE — `.
///
/// It is nine code units - six letters, a space, the em dash and a space -
/// and the em dash is one unit, so the length is worked out rather than
/// counted by hand.
///
const NOTICE_PREFIX : String = "NOTICE — "

///|
/// The message without its `NOTICE — ` prefix.
///
fn strip_notice_prefix(msg : String) -> String {
  if msg.has_prefix(NOTICE_PREFIX) {
    msg[NOTICE_PREFIX.length():msg.length()].to_owned()
  } else {
    msg
  }
}

///|
/// The source location of a NOTICE message, e.g. `77:15`.
///
pub fn notice_loc(msg : String) -> String {
  match msg.find(" @") {
    None => ""
    Some(i) => {
      let rest = msg[i + 2:msg.length()].to_owned()
      let mut end = 0
      let cs = chars(rest)
      while end < cs.length() && cs[end] != ' ' {
        end += 1
      }
      text(cs, 0, end)
    }
  }
}

///|
/// The message of a NOTICE, without the `NOTICE — ` prefix and the location.
///
pub fn notice_text(msg : String) -> String {
  let rest = strip_notice_prefix(msg)
  match rest.find(" — ") {
    None => rest
    Some(i) => rest[i + 3:rest.length()].to_owned()
  }
}
