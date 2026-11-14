///|
/// Assembling the printable document.

///|
/// The page order is fixed: cover, overview, detail, appendices. Every sheet
/// is A4 portrait with 12 mm margins, which leaves 186 x 273 mm of usable
/// area.
///
/// The overview is not printed as one drawing. The whole scan is 1,117 x
/// 25,160 px; printed whole it would be scaled to 3 % and unreadable. So it
/// is re-rendered as nineteen slices of twelve files each, every slice a real
/// Mermaid diagram with the real edge labels.
///
/// The one file with an actionable finding is printed differently, because
/// its drawing is a 16,302 px wide strip whose 27 NOTICE states each carry
/// the same footnote. Slicing that strip cost thirteen sheets and left every
/// label at roughly 8 px, and the finding sat at x=309 while the note that
/// explains it sat at x=11,849 - nine sheets apart. Instead it is printed as
///
///   1. a KEY MAP of the whole strip: the real diagram scaled to the page
///      width, with tick marks showing where the chain, the notice fan and
///      the finding are. It is a map, not a readable drawing.
///   2. the FINDING, enlarged, cropped out of the real SVG.
///   3. the NOTICES as a list, with the footnote they all share printed once
///      instead of once per notice.
///
/// Every number in the document is computed here, in MoonBit, from the
/// parsed model and from the geometry the browser measured. The browser
/// renders the diagrams and turns the sheets into a PDF; it decides nothing.
///

///|
/// The width of the printable area, in CSS pixels: 186 mm.
///
pub const WC_PX : Double = 186.0 * 96.0 / 25.4

///|
/// The height of a printable sheet, in CSS pixels: 273 mm.
///
pub const PAGE_H_PX : Double = 273.0 * 96.0 / 25.4

///|
/// The height of a page caption, in CSS pixels: 14 pt of line plus 4 pt of
/// margin below it.
///
pub const CAP_PX : Double = 18.0 * 96.0 / 72.0

///|
/// The height of the crop window that sits under a caption.
///
pub const HC_PX : Double = PAGE_H_PX - CAP_PX

///|
/// The rules the print layout adds to the stylesheet.
///
/// The crop window is a fixed box, and the diagram inside it is scaled to
/// fit - which is exactly what an SVG with a viewBox does when it is given
/// the box as its viewport and told to meet (not slice) it. So the browser
/// needs no script to scale the drawings: the mathematics of the scale is
/// the viewBox's, and the page still decides what goes on it.
///
pub const PRINT_CSS_EXTRA : String = ".crop>.holder.fit{width:100%;height:100%}" +
  // The one-page mode: the page is a column that spends one caption line at
  // the top and gives everything else to the drawing. The holder is the whole
  // remaining box, and the SVG fills it with `preserveAspectRatio`, so the
  // browser does the fitting and no scale has to be computed here.
  ".onepage{display:flex;flex-direction:column;height:273mm}" +
  ".onepage .fitbox{flex:1;position:relative;min-height:0}" +
  ".onepage .fitbox>.holder{position:absolute;left:0;top:0;width:100%;height:100%}" +
  ".onepage .fitbox svg{display:block}"

///|
/// What is going to be printed.
///
pub struct PrintPlan {
  /// the file index ranges of the overview slices
  slices : Array[(Int32, Int32)]
  /// the source of each overview slice
  slice_sources : Array[String]
  /// the index of the file with an actionable finding, or -1
  detail_index : Int32
  /// the id of the file with an actionable finding
  detail_id : String
  /// the source of that file's whole diagram
  detail_full : String
  /// the source of that file's focused diagram
  detail_focus : String
  /// how many NOTICE states that file carries
  detail_notices : Int32
}

///|
/// Decide what is going to be printed.
///
pub fn plan(d : @mermaid.Diagram) -> PrintPlan {
  let groups = slice_groups(d.files.length(), SLICE_FILES)
  let slices : Array[(Int32, Int32)] = []
  let sources : Array[String] = []
  for g in groups {
    slices.push(g)
    sources.push(slice_source(d, g.0, g.1))
  }
  let mut detail_index = -1
  for i in 0..<d.files.length() {
    if d.files[i].actionable > 0 {
      detail_index = i
      break
    }
  }
  let mut detail_full = ""
  let mut detail_focus = ""
  let mut detail_notices = 0
  let mut detail_id = ""
  if detail_index >= 0 {
    let f = d.files[detail_index]
    detail_full = @mermaid.file_source(f)
    detail_focus = focus_source(f)
    detail_notices = @mermaid.drawn_file_notices(f)
    detail_id = f.id
  }
  {
    slices,
    slice_sources: sources,
    detail_index,
    detail_id,
    detail_full,
    detail_focus,
    detail_notices,
  }
}

///|
/// The number of whole pages a width of diagram would need at 1:1.
///
fn pages_at_1to1(w : Double) -> Int32 {
  (w / WC_PX).ceil().to_int()
}

///|
/// One overview slice: a caption and a crop window.
///
fn slice_page_html(caption : String, slot : Int32) -> String {
  let sb = StringBuilder()
  sb.write_string("<div class=\"page\">\n<p class=\"slice-cap\">")
  sb.write_string(esc(caption))
  sb.write_string("</p>\n<div class=\"crop\" style=\"width:")
  sb.write_string(WC_PX.to_string())
  sb.write_string("px;height:")
  sb.write_string(HC_PX.to_string())
  sb.write_string("px\"><div class=\"holder fit\" data-slot=\"")
  sb.write_string(slot.to_string())
  sb.write_string("\"></div></div>\n</div>\n")
  sb.to_string()
}

///|
/// The key map of the whole strip, the table of its regions, and the note
/// that explains why the strip is printed as a map.
///
fn keymap_page_html(
  d : @mermaid.Diagram,
  p : PrintPlan,
  m : Measurement,
  slice_count : Int32,
  slot : Int32,
) -> String {
  let f = d.files[p.detail_index]
  let cls = classify(m.nodes, p.detail_id)
  let (full_w, full_h) = full_size(m)
  let map_h = if full_w > 0.0 { full_h / full_w * WC_PX } else { 0.0 }
  let to_px = fn(x : Double) -> Double {
    if full_w > 0.0 {
      x / full_w * WC_PX
    } else {
      0.0
    }
  }
  let clamp = fn(x : Double) -> Double {
    if x < 22.0 {
      22.0
    } else if x > WC_PX - 22.0 {
      WC_PX - 22.0
    } else {
      x
    }
  }
  let enlarged_page = slice_count + 3
  let list_page = slice_count + 4
  let sb = StringBuilder()
  sb.write_string("<div class=\"page\">\n<p class=\"slice-cap\">")
  sb.write_string(
    esc(
      "Detail " +
      p.detail_id +
      " - " +
      f.path +
      " - key map of the full diagram (" +
      fmt0(full_w) +
      " x " +
      fmt0(full_h) +
      " px)",
    ),
  )
  sb.write_string("</p>\n<div class=\"km\">\n<div class=\"km-svg\">")
  sb.write_string("<div class=\"holder map\" data-slot=\"")
  sb.write_string(slot.to_string())
  sb.write_string("\" data-mode=\"map\" data-w=\"")
  sb.write_string(WC_PX.to_string())
  sb.write_string("\" data-h=\"")
  sb.write_string(map_h.to_string())
  sb.write_string("\"></div>\n")
  // the band that holds the identical footnotes
  let b_l = to_px(cls.boiler.from)
  let b_w = to_px(cls.boiler.to) - b_l
  sb.write_string("<i class=\"km-band\" style=\"left:")
  sb.write_string(fmt1(b_l))
  sb.write_string("px;width:")
  sb.write_string(fmt1(b_w))
  sb.write_string("px\"></i>\n")
  // a tick under every NOTICE state
  for i in 0..<cls.state_x.length() {
    sb.write_string("<i class=\"km-tick\" style=\"left:")
    sb.write_string(fmt1(to_px(cls.state_x[i])))
    sb.write_string("px\"></i>\n")
  }
  let has_defect = cls.defect.to > cls.defect.from
  let has_why = cls.why.to > cls.why.from
  let defect_c = (cls.defect.from + cls.defect.to) / 2.0
  let why_c = (cls.why.from + cls.why.to) / 2.0
  if has_defect {
    sb.write_string("<i class=\"km-tick hot\" style=\"left:")
    sb.write_string(fmt1(clamp(to_px(defect_c))))
    sb.write_string("px\"></i>\n")
  }
  if has_why {
    sb.write_string("<i class=\"km-tick hot\" style=\"left:")
    sb.write_string(fmt1(clamp(to_px(why_c))))
    sb.write_string("px\"></i>\n")
  }
  sb.write_string("</div>\n<div class=\"km-labs\">\n")
  for i in 0..<cls.state_x.length() {
    if i % 7 == 0 || i == cls.state_x.length() - 1 {
      sb.write_string("<b class=\"km-lab\" style=\"left:")
      sb.write_string(fmt1(to_px(cls.state_x[i])))
      sb.write_string("px\">n")
      sb.write_string(i.to_string())
      sb.write_string("</b>\n")
    }
  }
  if has_defect {
    sb.write_string("<b class=\"km-lab hot\" style=\"left:")
    sb.write_string(fmt1(clamp(to_px(defect_c))))
    sb.write_string("px\">the finding</b>\n")
  }
  if has_why {
    sb.write_string("<b class=\"km-lab hot\" style=\"left:")
    sb.write_string(fmt1(clamp(to_px(why_c))))
    sb.write_string("px\">its WHY note</b>\n")
  }
  sb.write_string(
    "</div>\n<div class=\"km-labs\">\n<b class=\"km-lab band\" style=\"left:",
  )
  sb.write_string(fmt1(b_l + b_w / 2.0))
  sb.write_string("px\">")
  sb.write_string(cls.boiler_n.to_string())
  sb.write_string(" identical footnotes</b>\n</div>\n</div>\n")
  // the regions of the real drawing, and where each one is printed
  sb.write_string(
    "<table class=\"data keymap-tbl\">\n<thead><tr><th>region of the real diagram</th><th class=\"num\">x range (px)</th><th>what is there</th><th>where it is printed</th></tr></thead>\n<tbody>\n",
  )
  sb.write_string("<tr><td>trust chain</td><td class=\"num\">")
  sb.write_string(fmt0(cls.chain.from))
  sb.write_string("&ndash;")
  sb.write_string(fmt0(cls.chain.to))
  sb.write_string("</td><td>scan &rarr; ")
  sb.write_string(esc(p.detail_id))
  sb.write_string(
    " &rarr; lexed &rarr; inspection 1/3 &rarr; 2/3 &rarr; 3/3</td><td>page ",
  )
  sb.write_string(enlarged_page.to_string())
  sb.write_string(", enlarged</td></tr>\n")
  sb.write_string("<tr><td>NOTICE states</td><td class=\"num\">")
  sb.write_string(fmt0(cls.states.from))
  sb.write_string("&ndash;")
  sb.write_string(fmt0(cls.states.to))
  sb.write_string("</td><td>")
  sb.write_string(cls.states_n.to_string())
  sb.write_string(
    " NOTICE states, each with an identical footnote</td><td>page ",
  )
  sb.write_string(list_page.to_string())
  sb.write_string(", as a list</td></tr>\n")
  sb.write_string("<tr><td>their footnotes</td><td class=\"num\">")
  sb.write_string(fmt0(cls.boiler.from))
  sb.write_string("&ndash;")
  sb.write_string(fmt0(cls.boiler.to))
  sb.write_string("</td><td>")
  sb.write_string(cls.boiler_n.to_string())
  sb.write_string(
    " copies of one and the same text &mdash; half the width of the drawing</td><td>page ",
  )
  sb.write_string(list_page.to_string())
  sb.write_string(", printed once</td></tr>\n")
  sb.write_string("<tr class=\"hot\"><td>the finding</td><td class=\"num\">")
  sb.write_string(fmt0(cls.defect.from))
  sb.write_string("&ndash;")
  sb.write_string(fmt0(cls.defect.to))
  sb.write_string("</td><td>")
  sb.write_string(esc(finding_label(f)))
  sb.write_string(" &mdash; the only defect in the whole scan</td><td>page ")
  sb.write_string(enlarged_page.to_string())
  sb.write_string(", enlarged</td></tr>\n")
  sb.write_string("<tr class=\"hot\"><td>its WHY note</td><td class=\"num\">")
  sb.write_string(fmt0(cls.why.from))
  sb.write_string("&ndash;")
  sb.write_string(fmt0(cls.why.to))
  sb.write_string("</td><td>the explanation &mdash; <b>")
  sb.write_string(group((cls.why.from - cls.defect.from).round().to_int()))
  sb.write_string(" px away from the finding</b></td><td>page ")
  sb.write_string(enlarged_page.to_string())
  sb.write_string(", enlarged</td></tr>\n")
  sb.write_string("</tbody>\n</table>\n")
  // why a map and not the drawing
  sb.write_string(
    "<p class=\"lede\">The strip above is the <em>real</em> diagram, scaled to ",
  )
  sb.write_string(fmt1(full_w / WC_PX))
  sb.write_string(
    ":1 so that its whole width fits the page. It is a map, not a readable drawing &mdash; its text is far below print size. ",
  )
  sb.write_string(group(full_w.round().to_int()))
  sb.write_string(" px of diagram cannot be shown at 1:1 on ")
  sb.write_string(pages_at_1to1(full_w).to_string())
  sb.write_string(
    " A4 pages; the previous edition squeezed it onto 13 sheets, which left every label at roughly 8&nbsp;px and put the one actionable finding (x&nbsp;",
  )
  sb.write_string(fmt0(cls.defect.from))
  sb.write_string(") on one sheet and the note explaining it (x&nbsp;")
  sb.write_string(fmt0(cls.why.from))
  sb.write_string(
    ") about nine sheets later. The next two pages give that finding at full size and the ",
  )
  sb.write_string(cls.states_n.to_string())
  sb.write_string(" notices as a list.</p>\n</div>\n")
  sb.to_string()
}

///|
/// The actionable finding of a file, as `Kind @line:column`.
///
fn finding_label(f : @mermaid.FileBlock) -> String {
  for s in f.states {
    if !@mermaid.is_notice(s.msg) &&
      !@mermaid.is_stage(s.msg) &&
      !@mermaid.is_file_label(f.id, s.msg) {
      match s.msg.find(" — ") {
        None => return s.msg
        Some(i) => return s.msg[0:i].to_owned()
      }
    }
  }
  ""
}

///|
/// The finding, enlarged: a caption and a crop window holding the focused
/// drawing.
///
fn enlarged_page_html(
  d : @mermaid.Diagram,
  p : PrintPlan,
  m : Measurement,
  slot : Int32,
) -> String {
  let f = d.files[p.detail_index]
  let (focus_w, focus_h) = focus_size(m)
  let sb = StringBuilder()
  sb.write_string("<div class=\"page\">\n<p class=\"slice-cap\">")
  sb.write_string(
    esc(
      "Detail " +
      p.detail_id +
      " - " +
      f.path +
      " - the one actionable finding, enlarged (real render, " +
      fmt0(focus_w) +
      " x " +
      fmt0(focus_h) +
      " px)",
    ),
  )
  sb.write_string("</p>\n<div class=\"crop\" style=\"width:")
  sb.write_string(WC_PX.to_string())
  sb.write_string("px;height:")
  sb.write_string(HC_PX.to_string())
  sb.write_string("px\"><div class=\"holder fit\" data-slot=\"")
  sb.write_string(slot.to_string())
  sb.write_string("\"></div></div>\n</div>\n")
  sb.to_string()
}

///|
/// The notices of the actionable file, as a list, with the footnote they all
/// share printed once.
///
fn notice_list_page_html(d : @mermaid.Diagram, p : PrintPlan) -> String {
  let f = d.files[p.detail_index]
  let notices = @mermaid.drawn_file_notices(f)
  let sb = StringBuilder()
  sb.write_string("<div class=\"page flow\">\n<p class=\"slice-cap\">")
  sb.write_string(
    esc("Detail " + p.detail_id + " - " + f.path + " - notice list"),
  )
  sb.write_string("</p>\n<h3 class=\"appx\">Detail ")
  sb.write_string(esc(p.detail_id))
  sb.write_string(" &mdash; the ")
  sb.write_string(notices.to_string())
  sb.write_string(" NOTICE states of this file</h3>\n")
  sb.write_string("<p class=\"lede\">In the source diagram every one of these ")
  sb.write_string(notices.to_string())
  sb.write_string(" states carries the same footnote, printed ")
  sb.write_string(notices.to_string())
  sb.write_string(
    " times side by side. The text is reproduced once, below the table, and the states are listed here instead of being drawn ",
  )
  sb.write_string(notices.to_string())
  sb.write_string(" times.</p>\n")
  sb.write_string("<blockquote class=\"boiler\">")
  sb.write_string(esc(fan_boilerplate(f)))
  sb.write_string("</blockquote>\n")
  sb.write_string(
    "<table class=\"data notices\">\n<thead><tr><th>state</th><th>kind</th><th>loc</th><th>message</th></tr></thead>\n<tbody>\n",
  )
  for s in f.states {
    if !@mermaid.is_notice(s.msg) {
      continue
    }
    sb.write_string("<tr><td class=\"mono\">")
    sb.write_string(esc(s.id))
    sb.write_string("</td><td>")
    sb.write_string(esc(notice_kind(s.msg)))
    sb.write_string("</td><td class=\"mono\">")
    sb.write_string(esc(notice_loc(s.msg)))
    sb.write_string("</td><td>")
    sb.write_string(esc(notice_text(s.msg)))
    sb.write_string("</td></tr>\n")
  }
  sb.write_string("</tbody>\n</table>\n</div>\n")
  sb.to_string()
}

///|
/// The script that renders the diagrams into their slots.
///
/// The only thing this script does is put a rendered drawing into the box
/// that the page has already reserved for it, and pin the drawing's own
/// size so that the browser scales it to the box. Which drawing goes where,
/// and how big the boxes are, was decided in MoonBit.
///
fn print_script() -> String {
  let lines = [
    "(function () {", "  var SRC = JSON.parse(document.getElementById('srcs').textContent);",
    "  window.mermaid.initialize({ startOnLoad: false, maxTextSize: 20000000, maxEdges: 500000, theme: 'default' });",
    "  function fit(svg, el) {", "    var m = svg.match(/viewBox=\"([^\"]+)\"/);",
    "    if (!m) { return svg; }", "    var vb = m[1];", "    var attrs;", "    if (el.dataset.mode === 'map') {",
    "      attrs = ' width=\"' + el.dataset.w + '\" height=\"' + el.dataset.h + '\" viewBox=\"' + vb + '\"';",
    "    } else if (el.dataset.mode === 'fit') {",
    // one page: the drawing fills its holder and the browser scales it down,
    // centred, so nothing is cropped and nothing spills onto a second sheet
     "      attrs = ' width=\"100%\" height=\"100%\" viewBox=\"' + vb + '\" preserveAspectRatio=\"xMidYMid meet\"';",
    "    } else {", "      attrs = ' width=\"100%\" height=\"100%\" viewBox=\"' + vb + '\" preserveAspectRatio=\"xMinYMin meet\"';",
    "    }", "    var s = svg.replace(/style=\"max-width:[^\"]*\"/, 'style=\"max-width:none\"');",
    "    s = s.replace(/<svg([^>]*)>/, function (whole, a) {", "      a = a.replace(/\\s*width=\"[^\"]*\"/, '');",
    "      a = a.replace(/\\s*height=\"[^\"]*\"/, '');", "      a = a.replace(/\\s*viewBox=\"[^\"]*\"/, '');",
    "      return '<svg' + a + attrs + '>';", "    });", "    return s;", "  }",
    "  var done = 0;", "  function step() {", "    if (done >= SRC.length) { document.title = 'print-ready'; return; }",
    "    var i = done;", "    done = done + 1;", "    var el = document.querySelector('[data-slot=\"' + i + '\"]');",
    "    if (!el) { step(); return; }", "    window.mermaid.render('p' + i, SRC[i]).then(function (r) {",
    "      el.innerHTML = fit(r.svg, el);", "      step();", "    }, function (e) {",
    "      el.textContent = 'render failed: ' + ((e && e.message) || String(e));",
    "      step();", "    });", "  }", "  step();", "})();",
  ]
  lines.join("\n")
}

///|
/// Build the whole scan as ONE page.
///
/// The report layout slices the drawing because a 16,302 px strip cropped into
/// readable windows is how the text stays legible. That is the right default
/// for reading, and the wrong one when what is wanted is "the picture, on a
/// page". This mode draws every file in one diagram and lets the browser scale
/// it down until it fits the sheet, so the result is exactly one page and
/// nothing is cut off.
///
/// The trade is stated rather than hidden: a diagram that is 9:1 becomes a wide
/// band on a portrait sheet, and its labels are small. The page is one page,
/// not a readable enlargement of one.
///
pub fn print_one_page(d : @mermaid.Diagram, mermaid_js : String) -> String {
  let src = slice_source(d, 0, d.files.length())
  let sources : Array[String] = [src]
  let caption = "the whole scan - " +
    d.files.length().to_string() +
    " files, " +
    @mermaid.drawn_notices(d).to_string() +
    " notice states, on one page"
  let sb = StringBuilder()
  sb.write_string(
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>",
  )
  sb.write_string(@mermaid.meta_of(d, "target"))
  sb.write_string(" &mdash; state diagram (one page)</title>\n<style>\n")
  sb.write_string(PRINT_CSS)
  sb.write_string(PRINT_CSS_EXTRA)
  sb.write_string("\n</style>\n</head>\n<body>\n")
  sb.write_string("<div class=\"page onepage\">\n<p class=\"slice-cap\">")
  sb.write_string(esc(caption))
  sb.write_string(
    "</p>\n<div class=\"fitbox\"><div class=\"holder\" data-slot=\"0\" data-mode=\"fit\"></div></div>\n</div>\n",
  )
  sb.write_string("<script type=\"application/json\" id=\"srcs\">")
  sb.write_string(sources_json(sources))
  sb.write_string("</script>\n<script id=\"rt\">")
  sb.write_string(mermaid_js.replace_all(old="</script", new="<\\/script"))
  sb.write_string("</script>\n<script>\n")
  sb.write_string(print_script())
  sb.write_string("\n</script>\n</body>\n</html>\n")
  sb.to_string()
}

///|
/// Build the complete printable document.
///
/// The browser is given the diagram sources and the boxes they go into; it
/// renders them and nothing else.
///
pub fn print_document(
  d : @mermaid.Diagram,
  p : PrintPlan,
  m : Measurement,
  mermaid_js : String,
) -> String {
  let slice_count = p.slices.length()
  let has_detail = p.detail_index >= 0
  // the sources the browser will render, in document order
  let sources : Array[String] = []
  for s in p.slice_sources {
    sources.push(s)
  }
  let full_slot = sources.length()
  if has_detail {
    sources.push(p.detail_full)
  }
  let focus_slot = sources.length()
  if has_detail {
    sources.push(p.detail_focus)
  }
  let sb = StringBuilder()
  sb.write_string(
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>",
  )
  sb.write_string(@mermaid.meta_of(d, "target"))
  sb.write_string(" &mdash; state diagram (print layout)</title>\n<style>\n")
  sb.write_string(PRINT_CSS)
  sb.write_string(PRINT_CSS_EXTRA)
  sb.write_string("\n</style>\n</head>\n<body>\n")
  sb.write_string(cover_html(d, p, m))
  for i in 0..<slice_count {
    let g = p.slices[i]
    let first = d.files[g.0].id
    let last = d.files[g.1 - 1].id
    let caption = "Overview " +
      (i + 1).to_string() +
      "/" +
      slice_count.to_string() +
      " — files " +
      first +
      ".." +
      last
    sb.write_string(slice_page_html(caption, i))
  }
  if has_detail {
    sb.write_string(keymap_page_html(d, p, m, slice_count, full_slot))
    sb.write_string(enlarged_page_html(d, p, m, focus_slot))
    sb.write_string(notice_list_page_html(d, p))
  }
  sb.write_string(file_table_html(d))
  sb.write_string(notice_table_html(d))
  sb.write_string("<script type=\"application/json\" id=\"srcs\">")
  sb.write_string(sources_json(sources))
  sb.write_string("</script>\n<script id=\"rt\">")
  sb.write_string(mermaid_js.replace_all(old="</script", new="<\\/script"))
  sb.write_string("</script>\n<script>\n")
  sb.write_string(print_script())
  sb.write_string("\n</script>\n</body>\n</html>\n")
  sb.to_string()
}
