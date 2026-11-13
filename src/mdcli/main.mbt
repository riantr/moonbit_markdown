///|
/// The command line tool.
///
/// Subcommands:
///   md2html <in.md> <out.html>              Markdown to a self-contained page
///   mmd2html <in.mmd> <out.html>            a Mermaid scan to the page
///   print2pdf <in.html> <out.pdf>           an HTML page to PDF, via Chrome
///   md2pdf <in.md> <out.pdf>                Markdown to PDF in one step
///   mmd2pdf <in.mmd> <out.pdf>              a Mermaid scan to PDF in one step
///   mmd2measure <in.mmd>                    the measured geometry of a scan
///
/// Options:
///   --mermaid-js <path>   the mermaid runtime to inline (default: the copy
///                          inside the mermaid-cli npm package)
///   --chrome <path>       the Chrome/Edge binary to drive for PDF output
///   --header-footer       let the browser print its own header and footer
///                          (off by default: the document has its own margins)
///   --figures-one-page    one diagram, one page: the drawing gets a page to
///                          itself and is scaled down until it fits, instead
///                          of being broken across two sheets (off by default)
///   --figure-page-fit <pt> one diagram, one page, sized to the diagram: each
///                          figure page is a sheet big enough for the labels
///                          inside the drawing to print at <pt> (implies
///                          --figures-one-page)
///   --figure-page-max <p>  the largest sheet --figure-page-fit may ask for:
///                          A6..A0, or <w>x<h>mm (default: A2)
///
/// The figure-page flags exist because a PDF is read, while the Markdown it
/// came from is parsed: one paper size for the whole document forces a choice
/// between wasting the small drawings and shrinking the large ones past
/// reading. Splitting the difference per page is what CSS named pages are for,
/// and the size a drawing needs is measured from the drawing itself.
///
/// NOTE ON EXIT CODES: MoonBit exposes no process-exit entry point in the
/// packages available here, so a failure prints an ERROR line on stderr and
/// the process still exits 0. A caller must read the output, not the exit
/// code. This is the same limitation riantr/moonbit_static_analysis records.

///|
const DEFAULT_MERMAID_JS : String = "C:\\Users\\hp\\AppData\\Roaming\\npm\\node_modules\\@mermaid-js\\mermaid-cli\\node_modules\\mermaid\\dist\\mermaid.min.js"

///|
const DEFAULT_CHROME : String = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"

///|
/// The largest sheet the figure-page mode may ask for.
const DEFAULT_FIGURE_PAGE_MAX : String = "A2"

///|
/// The smallest sheet the figure-page mode may ask for: below this the page
/// reads as a mistake rather than as a page.
const FIGURE_PAGE_MIN : String = "A5"

///|
fn usage() -> Unit {
  println("riantr/moonbit_markdown")
  println("")
  println(
    "  md2html <in.md> <out.html>              Markdown to a self-contained page",
  )
  println(
    "  mmd2html <in.mmd> <out.html>            a Mermaid scan to the page",
  )
  println(
    "  print2pdf <in.html> <out.pdf>           an HTML page to PDF, via Chrome",
  )
  println(
    "  md2pdf <in.md> <out.pdf>                Markdown to PDF in one step",
  )
  println(
    "  mmd2pdf <in.mmd> <out.pdf>              a Mermaid scan to PDF in one step",
  )
  println(
    "  mmd2measure <in.mmd>                    the measured geometry of a scan",
  )
  println("")
  println("  --mermaid-js <path>    the mermaid runtime to inline")
  println("  --chrome <path>        the Chrome binary to drive for PDF output")
  println(
    "  --header-footer        let the browser print its own header and footer",
  )
  println(
    "  --figures-one-page     give each diagram a page of its own, scaled to fit",
  )
  println(
    "  --figure-page-fit <pt> give each diagram a sheet sized to it, so its",
  )
  println(
    "                         labels print at <pt> (default when used: 6)",
  )
  println(
    "  --figure-page-max <p>  the largest sheet to ask for: A6..A0 or WxHmm",
  )
  println("                         (default: A2)")
}

///|
/// The argument index of the first user argument.
///
/// `@env.args()` starts with the program itself. Under the js backend it
/// starts with the node binary AND the script path, so two entries have to
/// be skipped there; under native only one.

///|
fn user_arg_start(args : Array[String]) -> Int32 {
  if args.length() > 0 {
    let a = args[0]
    if a.has_suffix(".js") || a.has_suffix(".mjs") {
      return 2
    }
  }
  1
}

///|
async fn read_text(path : String) -> String? {
  if !@fs.exists(path) {
    println("ERROR\tno such file: \{path}")
    return None
  }
  let data = @fs.read_file(path)
  let t = data.text() catch {
    e => {
      println("ERROR\tcannot read \{path}: \{e}")
      return None
    }
  }
  Some(t)
}

///|
async fn write_text(path : String, content : String) -> Unit {
  @fs.write_file(path, content)
  println("wrote \{path} (\{(content.length() / 1024)} KB)")
}

///|
/// The document title of an HTML page, taken from its file name.
///
fn file_title(path : String) -> String {
  let cs = @text.chars(path)
  let mut start = 0
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '/' || cs[i] == '\\' {
      start = i + 1
    }
    i += 1
  }
  let mut dot = -1
  let mut i = start
  while i < cs.length() {
    if cs[i] == '.' {
      dot = i
    }
    i += 1
  }
  if dot > start {
    @text.text(cs, start, dot)
  } else {
    @text.text(cs, start, cs.length())
  }
}

///|
/// Build the HTML5 page for a Mermaid scan.
///
async fn mmd_to_html(
  in_path : String,
  out_path : String,
  mermaid_js_path : String,
) -> Unit {
  match read_text(in_path) {
    Some(src) => {
      let d = @mermaid.parse_diagram(src)
      println(
        "parsed \{d.files.length()} files, \{@mermaid.drawn_notices(d)} notice states, \{@mermaid.drawn_findings(d)} findings",
      )
      let mermaid_js = match read_text(mermaid_js_path) {
        Some(js) => js
        None => {
          // the scan page IS a Mermaid application: the client script draws
          // the overview, the sidebar and every sub-diagram. Without the
          // runtime there is nothing to show, so nothing is written - the same
          // rule the measure and print steps already follow.
          println(
            "ERROR\tcannot inline the mermaid runtime; the page cannot draw the diagram, so no page was written",
          )
          return
        }
      }
      let title = @mermaid.meta_of(d, "target") +
        " — Mermaid state diagram (HTML5 render)"
      let page = @mermaid.render_page(d, mermaid_js, title, src)
      write_text(out_path, page)
    }
    None => ()
  }
}

///|
/// Build the HTML5 page for a Markdown document.
///
/// The mermaid runtime is 2.6 MB, so it is only inlined when the document
/// actually holds a diagram: a page without one stays a page without it.
///
///|
/// A document, ready to be written as a page: its blocks (which the figure
/// measurement walks), its rendered body, and the runtime that draws it.
priv struct RenderedDoc {
  blocks : Array[@md.Block]
  body : String
  mermaid_js : String
}

///|
/// Parse and render the document, or report why it cannot be drawn.
///
/// `md2html` and `md2pdf` both need exactly this, and a document whose diagram
/// cannot be drawn has to fail the same way through either, so the first half
/// of both lives here.
async fn render_document(in_path : String, mermaid_js_path : String) -> RenderedDoc? {
  match read_text(in_path) {
    Some(src) => {
      let blocks = @md.parse_document(src)
      let body = @md.render_blocks(blocks)
      let mermaid_js = if @md.needs_runtime(blocks) {
        match read_text(mermaid_js_path) {
          Some(js) => js
          None => {
            // the document holds a diagram, so it needs the runtime; a page
            // whose diagram would only show its source is not worth writing
            println(
              "ERROR\tcannot inline the mermaid runtime; the diagram cannot be drawn, so no page was written",
            )
            return None
          }
        }
      } else {
        ""
      }
      Some({ blocks, body, mermaid_js })
    }
    None => None
  }
}

///|
async fn md_to_html(
  in_path : String,
  out_path : String,
  mermaid_js_path : String,
  figures_one_page : Bool,
) -> Unit {
  match render_document(in_path, mermaid_js_path) {
    Some(doc) => {
      let page = @md.render_page(
        file_title(in_path),
        doc.body,
        doc.mermaid_js,
        figures_one_page~,
      )
      write_text(out_path, page)
    }
    None => ()
  }
}

///|
/// Lay out one sheet per drawing, and return the stylesheet fragment that
/// hands them out.
///
/// The measurement is a round trip through the browser because a drawing's
/// size is only known once the drawing exists; the arithmetic that turns those
/// sizes into sheets is `@md.figure_pages`. The result is reported per figure
/// on purpose: when `--figure-page-max` bites, the labels land below the
/// target, and a silent degradation is the one thing this mode must not do.
async fn figure_page_sheets(
  doc : RenderedDoc,
  chrome : String,
  target_pt : Double,
  max_spec : String,
) -> String? {
  let sources = @md.mermaid_sources(doc.blocks)
  if sources.is_empty() {
    println("NOTE\tthis document holds no diagram, so the page size is unchanged")
    return Some("")
  }
  let max_mm = match @md.paper_of(max_spec) {
    Some(p) => p
    None => {
      println("ERROR\tunknown paper size for --figure-page-max: " + max_spec)
      return None
    }
  }
  let min_mm = match @md.paper_of(FIGURE_PAGE_MIN) {
    Some(p) => p
    None => (148.0, 210.0)
  }
  let measure_path = "measure.html"
  @fs.write_file(measure_path, @printpdf.measure_page(sources, doc.mermaid_js))
  let dom = match dump_dom(chrome, measure_path) {
    Some(x) => x
    None => {
      println("ERROR\tthe browser did not return the measurement")
      @fs.remove(measure_path)
      return None
    }
  }
  @fs.remove(measure_path)
  let m = @printpdf.parse_measurement(dom)
  for e in m.errors {
    println("ERROR\ta diagram did not render: " + e)
  }
  let pages = @md.figure_pages(
    m.dims,
    m.fonts,
    target_pt,
    max_mm,
    min_mm,
    @md.FIGURE_MARGIN_MM,
  )
  for p in pages {
    let mut line = "figure " + p.index.to_string() + "\t" +
      @printpdf.fmt1(p.width_mm) +
      " x " +
      @printpdf.fmt1(p.height_mm) +
      " mm\tlabels " +
      @printpdf.fmt1(p.label_pt) +
      " pt"
    if p.capped {
      line = line + "\tcapped by --figure-page-max"
    }
    println(line)
  }
  Some(@md.figure_page_css(pages, @md.FIGURE_MARGIN_MM))
}

///|
/// Render a Markdown document to PDF, optionally with a sheet per figure.
///
/// With a figure target the document is laid out twice: once so the browser
/// can measure the drawings, once with the sheets those measurements imply.
/// Nothing in the second pass is guessed - the first pass is what makes the
/// second possible.
async fn md_to_pdf(
  in_path : String,
  out_path : String,
  mermaid_js_path : String,
  chrome : String,
  header_footer : Bool,
  figures_one_page : Bool,
  figure_fit_pt : Double?,
  figure_max : String,
) -> Unit {
  match render_document(in_path, mermaid_js_path) {
    Some(doc) => {
      let mut extra_css = ""
      let mut one_page = figures_one_page
      match figure_fit_pt {
        None => ()
        Some(pt) =>
          match figure_page_sheets(doc, chrome, pt, figure_max) {
            Some(css) => {
              // a sheet per figure is a page per figure, so this mode implies
              // the one-page layout rather than stacking two layouts
              one_page = true
              extra_css = css
            }
            None => return
          }
      }
      let page = @md.render_page(
        file_title(in_path),
        doc.body,
        doc.mermaid_js,
        figures_one_page=one_page,
        extra_print_css=extra_css,
      )
      let tmp = sidecar_path(out_path, ".html")
      write_text(tmp, page)
      print_to_pdf(tmp, out_path, chrome, header_footer)
    }
    None => ()
  }
}

///|
/// Measure a Mermaid scan's detail drawing and report the geometry.
///
/// This is the first half of the print chain, on its own: it renders the
/// actionable file's drawing in the browser, reads the geometry of every
/// node back, and prints it. It is how the print layout gets the numbers it
/// needs - and how those numbers can be checked against the drawing.
///
async fn mmd_to_measure(
  in_path : String,
  mermaid_js_path : String,
  chrome : String,
) -> Unit {
  match read_text(in_path) {
    Some(src) => {
      let d = @mermaid.parse_diagram(src)
      let p = @printpdf.plan(d)
      let mermaid_js = match read_text(mermaid_js_path) {
        Some(js) => js
        None => {
          println("ERROR\tcannot inline the mermaid runtime")
          return
        }
      }
      let measure_path = "measure.html"
      @fs.write_file(
        measure_path,
        @printpdf.measure_page([p.detail_full, p.detail_focus], mermaid_js),
      )
      let dom = match dump_dom(chrome, measure_path) {
        Some(x) => x
        None => {
          println("ERROR\tthe browser did not return the measurement")
          return
        }
      }
      let m = @printpdf.parse_measurement(dom)
      let (w, h) = @printpdf.full_size(m)
      let (fw, fh) = @printpdf.focus_size(m)
      println(
        "full:   \{@printpdf.fmt0(w)} x \{@printpdf.fmt0(h)} px in \{m.nodes.length()} nodes",
      )
      println("focused: \{@printpdf.fmt0(fw)} x \{@printpdf.fmt0(fh)} px")
      for e in m.errors {
        println("ERROR\t\{e}")
      }
      for n in m.nodes {
        println(
          "node\t\{n.id}\t\{@printpdf.fmt0(n.x)}\t\{@printpdf.fmt0(n.y)}\t\{@printpdf.fmt0(n.w)}\t\{@printpdf.fmt0(n.h)}",
        )
      }
      let cls = @printpdf.classify(m.nodes, p.detail_id)
      println(
        "chain  \{@printpdf.fmt0(cls.chain.from)}-\{@printpdf.fmt0(cls.chain.to)}",
      )
      println(
        "states \{@printpdf.fmt0(cls.states.from)}-\{@printpdf.fmt0(cls.states.to)} (\{cls.states_n})",
      )
      println(
        "boiler \{@printpdf.fmt0(cls.boiler.from)}-\{@printpdf.fmt0(cls.boiler.to)} (\{cls.boiler_n})",
      )
      println(
        "defect \{@printpdf.fmt0(cls.defect.from)}-\{@printpdf.fmt0(cls.defect.to)}",
      )
      println(
        "why    \{@printpdf.fmt0(cls.why.from)}-\{@printpdf.fmt0(cls.why.to)}",
      )
      @fs.remove(measure_path)
    }
    None => ()
  }
}

///|
/// The path of a sidecar file next to the output.
///
/// `out.pdf` becomes `out.print.html` and `out.measure.html`, so the two
/// intermediate pages can be looked at, or printed again, next to the
/// document they produced.
///
fn sidecar_path(out_path : String, suffix : String) -> String {
  let cs = @text.chars(out_path)
  let mut dot = -1
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '.' {
      dot = i
    }
    i += 1
  }
  if dot > 0 {
    out_path[0:dot].to_owned() + suffix
  } else {
    out_path + suffix
  }
}

///|
/// Print a Mermaid scan as a paginated PDF.
///
/// The chain has three steps, and the algorithm is in the middle one:
///
///   1. the browser renders the actionable file's diagram and reports the
///      geometry of every node in it;
///   2. MoonBit reads that geometry back and lays out the document: the
///      cover, the overview slices, the key map with its tick marks, the
///      enlarged finding, the notice list and the two appendices;
///   3. the browser renders the sheets that MoonBit laid out and prints them
///      to PDF.
///
/// Nothing in the layout is left to the browser, and nothing is left to the
/// PDF: the notice count in the appendix is the notice count of the source.
///
async fn mmd_to_pdf(
  in_path : String,
  out_path : String,
  mermaid_js_path : String,
  chrome : String,
  header_footer : Bool,
  figures_one_page : Bool,
) -> Unit {
  match read_text(in_path) {
    Some(src) => {
      let d = @mermaid.parse_diagram(src)
      println(
        "parsed \{d.files.length()} files, \{@mermaid.drawn_notices(d)} notice states, \{@mermaid.drawn_findings(d)} findings",
      )
      let mermaid_js = match read_text(mermaid_js_path) {
        Some(js) => js
        None => {
          println("ERROR\tcannot inline the mermaid runtime")
          return
        }
      }
      let p = @printpdf.plan(d)
      if figures_one_page {
        // the whole drawing on one sheet: there is nothing to measure and
        // nothing to slice, so the report geometry has no say here
        let print_path = sidecar_path(out_path, ".print.html")
        @fs.write_file(print_path, @printpdf.print_one_page(d, mermaid_js))
        println("wrote \{print_path} (\{@fs.file_size(print_path) / 1024} KB)")
        print_to_pdf(print_path, out_path, chrome, header_footer)
        return
      }
      if p.detail_index < 0 {
        println(
          "ERROR\tthis scan has no file with an actionable finding, so there is no detail section",
        )
      }
      // ---- step 1: measure the detail drawing
      let measure_path = sidecar_path(out_path, ".measure.html")
      let sources = [p.detail_full, p.detail_focus]
      @fs.write_file(measure_path, @printpdf.measure_page(sources, mermaid_js))
      let dom = match dump_dom(chrome, measure_path) {
        Some(x) => x
        None => {
          println("ERROR\tthe browser did not return the measurement")
          @fs.remove(measure_path)
          return
        }
      }
      let m = @printpdf.parse_measurement(dom)
      if m.dims.is_empty() || m.nodes.is_empty() {
        println(
          "ERROR\tthe browser returned no geometry; the measurement page did not run",
        )
        println(
          "the measurement page is left at \{measure_path} for inspection",
        )
        return
      }
      if !m.errors.is_empty() {
        for e in m.errors {
          println("ERROR\tmeasure: \{e}")
        }
        @fs.remove(measure_path)
        return
      }
      let (w, h) = @printpdf.full_size(m)
      let (fw, fh) = @printpdf.focus_size(m)
      println(
        "measured the detail drawing: \{@printpdf.fmt0(w)} x \{@printpdf.fmt0(h)} px in \{m.nodes.length()} nodes; the focused drawing: \{@printpdf.fmt0(fw)} x \{@printpdf.fmt0(fh)} px",
      )
      // ---- step 2: lay the document out
      let print_path = sidecar_path(out_path, ".print.html")
      @fs.write_file(print_path, @printpdf.print_document(d, p, m, mermaid_js))
      println("wrote \{print_path} (\{@fs.file_size(print_path) / 1024} KB)")
      // ---- step 3: print it
      print_to_pdf(print_path, out_path, chrome, header_footer)
      @fs.remove(measure_path)
    }
    None => ()
  }
}

///|

///|
/// Run the command line tool with the given arguments (argv, argv[0] is the
/// program itself).
///
pub async fn run(args : Array[String]) -> Unit {
  let mut i = user_arg_start(args)
  if i >= args.length() {
    usage()
    return
  }
  let cmd = args[i]
  i += 1
  let positional : Array[String] = []
  let mut mermaid_js_path = DEFAULT_MERMAID_JS
  let mut chrome = DEFAULT_CHROME
  let mut header_footer = false
  let mut figures_one_page = false
  let mut figure_fit_pt : Double? = None
  let mut figure_max = DEFAULT_FIGURE_PAGE_MAX
  while i < args.length() {
    let a = args[i]
    if a == "--mermaid-js" && i + 1 < args.length() {
      i += 1
      mermaid_js_path = args[i]
    } else if a == "--chrome" && i + 1 < args.length() {
      i += 1
      chrome = args[i]
    } else if a == "--figures-one-page" {
      // one diagram, one page: the drawing is scaled down until it fits,
      // instead of being broken across two sheets
      figures_one_page = true
    } else if a == "--figure-page-fit" && i + 1 < args.length() {
      // one diagram, one sheet, and the sheet is sized to the drawing: this
      // is the mode where the PDF stops pretending every page is A4
      i += 1
      let pt = @printpdf.parse_num(args[i])
      if pt <= 0.0 {
        println("ERROR\t--figure-page-fit needs a size in points, above zero")
      } else {
        figure_fit_pt = Some(pt)
      }
    } else if a == "--figure-page-max" && i + 1 < args.length() {
      i += 1
      figure_max = args[i]
    } else if a == "--header-footer" {
      // the browser's own header and footer are off by default: the document
      // carries its own margins, and the browser's date-and-URL banner would
      // sit on top of them
      header_footer = true
    } else if a == "--no-header-footer" {
      header_footer = false
    } else {
      positional.push(a)
    }
    i += 1
  }
  match cmd {
    "md2html" => {
      if positional.length() < 2 {
        usage()
        return
      }
      md_to_html(positional[0], positional[1], mermaid_js_path, figures_one_page)
    }
    "mmd2html" => {
      if positional.length() < 2 {
        usage()
        return
      }
      mmd_to_html(positional[0], positional[1], mermaid_js_path)
    }
    "print2pdf" => {
      if positional.length() < 2 {
        usage()
        return
      }
      print_to_pdf(positional[0], positional[1], chrome, header_footer)
    }
    "md2pdf" => {
      if positional.length() < 2 {
        usage()
        return
      }
      md_to_pdf(
        positional[0],
        positional[1],
        mermaid_js_path,
        chrome,
        header_footer,
        figures_one_page,
        figure_fit_pt,
        figure_max,
      )
    }
    "mmd2measure" => {
      if positional.length() < 1 {
        usage()
        return
      }
      mmd_to_measure(positional[0], mermaid_js_path, chrome)
    }
    "mmd2pdf" => {
      if positional.length() < 2 {
        usage()
        return
      }
      mmd_to_pdf(
        positional[0],
        positional[1],
        mermaid_js_path,
        chrome,
        header_footer,
        figures_one_page,
      )
    }
    _ => usage()
  }
}
