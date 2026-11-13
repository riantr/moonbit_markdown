///|
/// Tests for the print layout.
///
/// Three things matter here and are easy to get wrong, so they are tested
/// directly:
///
///   - the geometry is classified by IDENTITY. Mermaid draws a note as a
///     node too, and the note text repeats the word NOTICE, so a text match
///     would count 27 states plus 27 note boxes.
///   - the focused source drops the notice fan and its duplicated footnotes,
///     and keeps everything else - including the note that explains the one
///     actionable finding.
///   - the appendices lose no row: one row per file, one row per notice
///     state, whatever the source says.
//|

///|
/// The fixture is a miniature of the generator's output: two files, one with
/// a NOTICE fan, one with an actionable finding.
///
fn fixture() -> String {
  let lines = [
    "%% target=riantr/moonbit_doubleML version=0.164.28 moonbit=0.1.20261012 files=2 parsed=2 partial=0 actionable=1 notices=2 unreliable=0 withheld=0 total=1",
    "stateDiagram-v2", "    direction TB", "    scan --> f1 : 0 actionable, 1 notice(s), parsed",
    "    state \"f1 — .repos/a/one.mbt\" as f1 {", "        direction TB", "        [*] --> f1_lex",
    "        state \"lexed\" as f1_lex", "        f1_lex --> f1_struct : whole file read",
    "        state \"inspection 1/3 — structural\" as f1_struct", "        f1_struct --> f1_n0 : notice ParseError",
    "        state \"NOTICE — ParseError @77:15 — if expression is outside the analyzed subset\" as f1_n0",
    "        note right of f1_n0", "            NOTICE — counted in `notices`, excluded from `actionable`.",
    "            ParseError covers a form this analyzer does not model.", "        end note",
    "    }", "    scan --> f98 : 1 actionable, 1 notice(s), parsed", "    state \"f98 — .repos/b/two.mbt\" as f98 {",
    "        direction TB", "        [*] --> f98_lex", "        state \"lexed\" as f98_lex",
    "        f98_lex --> f98_struct : whole file read", "        state \"inspection 1/3 — structural\" as f98_struct",
    "        f98_struct --> f98_e8 : defect OperatorMismatch", "        state \"OperatorMismatch @6795:17 — unsupported operand types\" as f98_e8",
    "        note right of f98_e8", "            WHY: One of four shapes.", "        end note",
    "        note right of f98_struct", "            1 of the findings on this file is a NOTICE.",
    "        end note", "        f98_struct --> f98_n0 : notice ParseError", "        state \"NOTICE — ParseError @77:15 — if expression is outside the analyzed subset\" as f98_n0",
    "        note right of f98_n0", "            NOTICE — counted in `notices`, excluded from `actionable`.",
    "            ParseError covers a form this analyzer does not model.", "        end note",
    "    }",
  ]
  lines.join("\n")
}

///|
/// How many times `needle` occurs in `haystack`.
///
fn count_of(haystack : String, needle : String) -> Int32 {
  let cs = @text.chars(haystack)
  let nc = @text.chars(needle)
  let mut n = 0
  let mut i = 0
  while i + nc.length() <= cs.length() {
    let mut hit = true
    let mut k = 0
    while k < nc.length() {
      if cs[i + k] != nc[k] {
        hit = false
        break
      }
      k += 1
    }
    if hit {
      n += 1
    }
    i += 1
  }
  n
}

///|
/// A measurement as the browser would report it.
///
fn measurement() -> @printpdf.Measurement {
  let boxes = [
    @printpdf.node_box("state-f98-0", 0.0, 0.0, 100.0, 20.0),
    @printpdf.node_box("state-f98_lex-1", 10.0, 30.0, 60.0, 20.0),
    @printpdf.node_box("state-f98_n0-2", 43.0, 7.0, 120.0, 30.0),
    @printpdf.node_box("state-f98_n0----note-3", 7709.0, 0.0, 230.0, 294.0),
    @printpdf.node_box("state-f98_e8-4", 309.0, 100.0, 80.0, 30.0),
    @printpdf.node_box("state-f98_e8----note-5", 11849.0, 0.0, 230.0, 294.0),
    @printpdf.node_box("state-f98_struct----note-6", 400.0, 0.0, 230.0, 294.0),
  ]
  @printpdf.measurement_of([(16302.0, 1819.0), (402.0, 318.0)], boxes)
}

///|
test "the focused source drops the notice fan and keeps the chain" {
  let d = @mermaid.parse_diagram(fixture())
  let focused = @printpdf.focus_source(d.files[1])
  // the fan is gone: its state, its edge and its duplicated footnote
  @test.assert_eq(focused.contains("f98_n0"), false)
  @test.assert_eq(focused.contains("notice ParseError"), false)
  // the chain, the file note, the finding and its WHY note stay
  @test.assert_eq(focused.contains("f98_lex"), true)
  @test.assert_eq(focused.contains("f98_struct"), true)
  @test.assert_eq(focused.contains("f98_e8"), true)
  @test.assert_eq(focused.contains("WHY: One of four shapes."), true)
  @test.assert_eq(
    focused.contains("1 of the findings on this file is a NOTICE."),
    true,
  )
  @test.assert_eq(
    focused.has_prefix("stateDiagram-v2\n    direction TB\n"),
    true,
  )
}

///|
test "the shared footnote is printed once, not once per notice" {
  let d = @mermaid.parse_diagram(fixture())
  let boiler = @printpdf.fan_boilerplate(d.files[1])
  @test.assert_eq(
    boiler.contains("counted in `notices`, excluded from `actionable`."),
    true,
  )
  @test.assert_eq(boiler.contains("ParseError covers a form"), true)
  // the file level note is not the boilerplate
  @test.assert_eq(boiler.contains("1 of the findings on this file"), false)
}

///|
test "the geometry is classified by identity, not by text" {
  let cls = @printpdf.classify(measurement().nodes, "f98")
  // one NOTICE state - the note box that shares its id shape is not a state
  @test.assert_eq(cls.states_n, 1)
  @test.assert_eq(cls.state_x.length(), 1)
  // one copy of the boilerplate footnote; the file level note is neither
  @test.assert_eq(cls.boiler_n, 1)
  // the finding and its WHY note are found apart
  @test.assert_eq(cls.defect.from, 309.0)
  @test.assert_eq(cls.defect.to, 389.0)
  @test.assert_eq(cls.why.from, 11849.0)
  @test.assert_eq(cls.why.to, 12079.0)
  // the chain holds the composite state and its inspections
  @test.assert_eq(cls.chain.from, 0.0)
}

///|
test "the crop boundaries fall in the gaps between the columns" {
  let intervals = [
    @printpdf.span(0.0, 100.0),
    @printpdf.span(200.0, 300.0),
    @printpdf.span(400.0, 500.0),
  ]
  let bounds = @printpdf.crop_boundaries(intervals, 600.0, 250.0)
  @test.assert_eq(bounds[0], 0.0)
  @test.assert_eq(bounds[bounds.length() - 1], 600.0)
  // ascending
  let mut i = 1
  while i < bounds.length() {
    @test.assert_eq(bounds[i] > bounds[i - 1], true)
    i += 1
  }
  // and no cut lands inside a column
  for b in bounds {
    for iv in intervals {
      @test.assert_eq(b > iv.from && b < iv.to, false)
    }
  }
}

///|
test "a drawing without columns is cut at the stride" {
  let bounds = @printpdf.crop_boundaries([], 1000.0, 250.0)
  @test.assert_eq(bounds, [0.0, 250.0, 500.0, 750.0, 1000.0])
}

///|
test "the overview is split into slices of twelve files" {
  let groups = @printpdf.slice_groups(221, 12)
  @test.assert_eq(groups.length(), 19)
  @test.assert_eq(groups[0], (0, 12))
  @test.assert_eq(groups[18], (216, 221))
}

///|
test "a slice is a real diagram with the real edge labels" {
  let d = @mermaid.parse_diagram(fixture())
  let src = @printpdf.slice_source(d, 0, 2)
  @test.assert_eq(src.has_prefix("stateDiagram-v2\n    direction LR\n"), true)
  @test.assert_eq(
    src.contains("scan --> f1 : 0 actionable, 1 notice(s), parsed"),
    true,
  )
  @test.assert_eq(
    src.contains("scan --> f98 : 1 actionable, 1 notice(s), parsed"),
    true,
  )
  // a slice is flat: no composite state, or dagre cannot lay it out
  @test.assert_eq(src.contains(" as f1 {"), false)
}

///|
test "the measurement comes back from the browser's DOM" {
  let dom = "<html><body><pre id=\"m\">BEGIN\nD\t0\t16302\t1819\nN\t0\tstate-f98_n0-2\t43\t7\t120\t30\nEND</pre></body></html>"
  let m = @printpdf.parse_measurement(dom)
  @test.assert_eq(m.dims.length(), 1)
  @test.assert_eq(m.dims[0].0, 16302.0)
  @test.assert_eq(m.dims[0].1, 1819.0)
  @test.assert_eq(m.nodes.length(), 1)
  @test.assert_eq(m.nodes[0].id, "state-f98_n0-2")
  @test.assert_eq(m.nodes[0].x, 43.0)
  @test.assert_eq(m.nodes[0].h, 30.0)
  @test.assert_eq(m.errors.length(), 0)
}

///|
test "only the first drawing's geometry is kept" {
  // the second drawing has its own coordinate space: 943 px wide against the
  // 16,302 px of the whole one, so its nodes must not be mixed in
  let dom = "<html><body><pre id=\"m\">BEGIN\nD\t0\t16302\t1819\nD\t1\t943\t1587\nN\t0\tstate-f98_e8-24\t309\t901\t216\t112\nN\t1\tstate-f98_e8-8\t309\t785\t216\t112\nEND</pre></body></html>"
  let m = @printpdf.parse_measurement(dom)
  @test.assert_eq(m.dims.length(), 2)
  @test.assert_eq(m.nodes.length(), 1)
  @test.assert_eq(m.nodes[0].id, "state-f98_e8-24")
}

///|
test "a failed measurement is reported, not swallowed" {
  let dom = "<html><body><pre id=\"m\">BEGIN\nE\t0\tCannot read properties of undefined\nEND</pre></body></html>"
  let m = @printpdf.parse_measurement(dom)
  @test.assert_eq(m.errors.length(), 1)
  @test.assert_eq(m.errors[0], "Cannot read properties of undefined")
}

///|
test "a NOTICE message is split into kind, location and text" {
  let msg = "NOTICE — ParseError @77:15 — if expression is outside the analyzed subset"
  @test.assert_eq(@printpdf.notice_kind(msg), "ParseError")
  @test.assert_eq(@printpdf.notice_loc(msg), "77:15")
  @test.assert_eq(
    @printpdf.notice_text(msg),
    "if expression is outside the analyzed subset",
  )
  // the prefix is nine code units, and the em dash is one of them
  @test.assert_eq("NOTICE — ".length(), 9)
}

///|
test "the appendix tables carry every row of the source" {
  let d = @mermaid.parse_diagram(fixture())
  let files = @printpdf.file_table_html(d)
  // one row per file, plus the header row
  @test.assert_eq(count_of(files, "<tr"), d.files.length() + 1)
  let notices = @printpdf.notice_table_html(d)
  @test.assert_eq(count_of(notices, "<tr"), @mermaid.drawn_notices(d) + 1)
  @test.assert_eq(count_of(notices, "f98_n0"), 1)
  // the kind of every notice is printed, not left out
  @test.assert_eq(count_of(notices, "ParseError"), @mermaid.drawn_notices(d))
}

///|
test "the print document has a page for every part" {
  let d = @mermaid.parse_diagram(fixture())
  let p = @printpdf.plan(d)
  @test.assert_eq(p.slices.length(), 1)
  @test.assert_eq(p.detail_index, 1)
  @test.assert_eq(p.detail_id, "f98")
  @test.assert_eq(p.detail_notices, 1)
  let doc = @printpdf.print_document(d, p, measurement(), "")
  // cover, one overview slice, three detail pages, two appendices
  @test.assert_eq(count_of(doc, "class=\"page"), 7)
  // one holder per drawing: the slice, the key map and the enlarged finding
  @test.assert_eq(count_of(doc, "class=\"holder"), 3)
  @test.assert_eq(doc.contains("Overview 1/1"), true)
}

///|
test "numbers are written the way the reference wrote them" {
  @test.assert_eq(@printpdf.fmt1(16302.0 / @printpdf.WC_PX), "23.2")
  @test.assert_eq(@printpdf.fmt0(16302.4), "16302")
  @test.assert_eq(@printpdf.group(16302), "16,302")
  @test.assert_eq(@printpdf.group(999), "999")
  @test.assert_eq(@printpdf.group(1000), "1,000")
  @test.assert_eq(@printpdf.group(2215), "2,215")
  @test.assert_eq(@printpdf.parse_num("1819.5"), 1819.5)
  @test.assert_eq(@printpdf.parse_num("16302"), 16302.0)
}

///|
test "the printable area is the size the layout assumes" {
  // 186 x 273 mm of paper inside A4 with 12 mm margins
  @test.assert_eq(@printpdf.fmt1(@printpdf.WC_PX * 25.4 / 96.0), "186.0")
  @test.assert_eq(@printpdf.fmt1(@printpdf.PAGE_H_PX * 25.4 / 96.0), "273.0")
  // the caption takes 14 pt of line and 4 pt of margin
  @test.assert_eq(@printpdf.CAP_PX, 24.0)
  // and what is left of the sheet is the crop window
  @test.assert_eq(@printpdf.fmt1(@printpdf.HC_PX * 25.4 / 96.0), "266.7")
  @test.assert_eq(@printpdf.HC_PX, @printpdf.PAGE_H_PX - @printpdf.CAP_PX)
}

///|
test "the one-page mode draws the whole scan once, with no slices" {
  let d = @mermaid.parse_diagram(fixture())
  let doc = @printpdf.print_one_page(d, "")
  // one page and one drawing: none of the slice machinery is used
  @test.assert_eq(count_of(doc, "class=\"page"), 1)
  @test.assert_eq(count_of(doc, "class=\"holder"), 1)
  // one holder, and the script reaches exactly that slot: the plain
  // `data-slot=` count would also match the selector in the script
  @test.assert_eq(count_of(doc, "data-slot=\"0\""), 1)
  // the scale is left to the browser, so the holder asks for fit rather than
  // for one of the two crop modes
  @test.assert_eq(doc.contains("data-mode=\"fit\""), true)
  @test.assert_eq(doc.contains("preserveAspectRatio=\"xMidYMid meet\""), true)
  @test.assert_eq(doc.contains("<div class=\"page onepage\">"), true)
  // the whole source goes to mermaid in one piece: both files are in it
  @test.assert_eq(doc.contains("f1 "), true)
  @test.assert_eq(doc.contains("f98"), true)
  // and the caption says what the page is, at the top of the page
  @test.assert_eq(doc.contains("2 files"), true)
  @test.assert_eq(
    doc.contains(@mermaid.drawn_notices(d).to_string() + " notice states"),
    true,
  )
  // no appendix travels with the one-page view
  @test.assert_eq(doc.contains("Appendix"), false)
}
